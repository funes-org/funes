module Funes
  # EventStream manages the append-only sequence of events for a specific entity.
  # Each stream is identified by an `idx` (entity identifier) and provides methods for appending
  # events and configuring how projections are triggered.
  #
  # EventStreams implement a three-tier consistency model:
  #
  # - **Consistency Projection:** Validates business rules before persisting the event. If invalid, the event is rejected.
  # - **Transactional Projections:** Execute synchronously in the same database transaction as the event.
  # - **Async Projections:** Execute asynchronously via ActiveJob after the event is committed.
  #
  # ## Bitemporal Queries
  #
  # EventStreams support two independent temporal dimensions:
  #
  # - **Record history** (`as_of`): Filters by `created_at` — "what did the system know at time T?"
  #   Set via `projected_with(projection, as_of: time)`.
  # - **Actual history** (`at`): Filters by `occurred_at` — "what had actually happened by time T?"
  #   Set via `projected_with(projection, at: time)`.
  #
  # When both are used together, `as_of` determines which events are visible (filtered in Ruby by
  # `created_at`), and `at` further narrows which of those events are projected (Ruby-level filter
  # on `occurred_at`).
  #
  # ## Actual Time Attribute
  #
  # Streams can declare an `actual_time_attribute` to automatically extract the actual time from
  # an event attribute. When configured, every event must have the attribute with a non-nil value.
  # The explicit `at:` on `append` takes precedence; if both are present and differ, a
  # {Funes::ConflictingActualTimeError} is raised.
  #
  # ## Concurrency Control
  #
  # EventStreams use optimistic concurrency control with version numbers. Each event gets an incrementing
  # version number with a unique constraint on `(idx, version)`, preventing race conditions when multiple
  # processes append to the same stream simultaneously.
  #
  # @example Define an event stream with projections
  #   class OrderEventStream < Funes::EventStream
  #     consistency_projection OrderValidationProjection
  #     add_transactional_projection OrderSnapshotProjection
  #     add_async_projection OrderReportProjection, queue: :reports
  #   end
  #
  # @example Define a stream with actual time extraction
  #   class SalaryEventStream < Funes::EventStream
  #     actual_time_attribute :effective_date
  #   end
  #
  # @example Append events to a stream
  #   stream = OrderEventStream.for("order-123")
  #   event = stream.append(Order::Placed.new(total: 99.99))
  #
  #   if event.valid?
  #     puts "Event persisted with version #{event.version}"
  #   else
  #     puts "Event rejected: #{event.errors.full_messages}"
  #   end
  #
  # @example Append a retroactive event with explicit actual time
  #   stream.append(Salary::Raised.new(amount: 6500), at: Time.new(2025, 2, 15))
  #
  # @example Actual history query - what had actually happened by a point in time
  #   stream = SalaryEventStream.for("sally-123")
  #   stream.projected_with(SalaryProjection, at: Time.new(2025, 2, 20))
  #
  # @example Full bitemporal query - combining both dimensions
  #   stream = SalaryEventStream.for("sally-123")
  #   stream.projected_with(SalaryProjection, as_of: Time.new(2025, 3, 1), at: Time.new(2025, 2, 20))
  class EventStream
    class << self
      # Register a consistency projection that validates business rules before persisting events.
      #
      # The consistency projection runs before the event is saved. If the resulting state is invalid,
      # the event is rejected and not persisted to the database.
      #
      # @param [Class<Funes::Projection>] projection The projection class that will validate the state.
      # @return [void]
      #
      # @example
      #   class InventoryEventStream < Funes::EventStream
      #     consistency_projection InventoryValidationProjection
      #   end
      def consistency_projection(projection)
        @consistency_projection = projection
      end

      # Register a transactional projection that executes synchronously in the same database transaction.
      #
      # Transactional projections run after the event is persisted but within the same database transaction.
      # If a transactional projection fails with a database error, the transaction is rolled back,
      # the event is marked as not persisted (`persisted?` returns false), and the exception propagates
      # to the caller. This fail-loud behavior ensures that bugs in projections (such as constraint
      # violations) are immediately visible rather than silently hidden.
      #
      # @param [Class<Funes::Projection>] projection The projection class to execute transactionally.
      # @return [void]
      # @raise [ActiveRecord::StatementInvalid] if the projection fails with a database error.
      #   The event will have `persisted?` returning false, allowing safe rescue in the host application.
      #
      # @example
      #   class OrderEventStream < Funes::EventStream
      #     add_transactional_projection OrderSnapshotProjection
      #   end
      def add_transactional_projection(projection)
        @transactional_projections ||= []
        @transactional_projections << projection
      end

      # Register an async projection that executes in a background job after the event is committed.
      #
      # Async projections are scheduled via ActiveJob after the event transaction commits. You can
      # pass any ActiveJob options (queue, wait, wait_until, priority, etc.) to control job scheduling.
      #
      # The `temporal_context` parameter controls the temporal reference passed to the projection job.
      # Its resolved value becomes the `at:` argument received by interpretation blocks. Note that
      # this is independent from the `at:` argument of `EventStream#append` — that value sets the
      # event's `occurred_at` (business time) and does not flow through to async projections.
      # - `:last_event_time` (default) - Uses the transaction time (`created_at`) of the last event,
      #   i.e. when it was recorded in the database, not when the business event occurred (`occurred_at`)
      # - `:job_time` - Uses Time.current when the job executes
      # - Proc/Lambda - Custom logic that receives the last event and returns a Time object
      #
      # @param [Class<Funes::Projection>] projection The projection class to execute asynchronously.
      # @param [Symbol, Proc] temporal_context Strategy for determining the temporal reference (:last_event_time, :job_time, or Proc).
      # @param [Hash] options ActiveJob options for scheduling (queue, wait, wait_until, priority, etc.).
      # @return [void]
      #
      # @example Schedule with custom queue
      #   class OrderEventStream < Funes::EventStream
      #     add_async_projection OrderReportProjection, queue: :reports
      #   end
      #
      # @example Schedule with delay
      #   class OrderEventStream < Funes::EventStream
      #     add_async_projection AnalyticsProjection, wait: 5.minutes
      #   end
      #
      # @example Use job execution time instead of event time
      #   class OrderEventStream < Funes::EventStream
      #     add_async_projection RealtimeProjection, temporal_context: :job_time
      #   end
      #
      # @example Custom temporal_context logic with proc
      #   class OrderEventStream < Funes::EventStream
      #     add_async_projection EndOfDayProjection, temporal_context: ->(last_event) { last_event.created_at.beginning_of_day }
      #   end
      def add_async_projection(projection, temporal_context: :last_event_time, **options)
        @async_projections ||= []
        @async_projections << { class: projection, temporal_context: temporal_context, options: options }
      end

      # Configures the event attribute used as a source for the actual time (`occurred_at`).
      #
      # When set, every event appended to this stream must have the specified attribute.
      # Its value is used as the fallback for `occurred_at` when `at:` is not explicitly
      # passed to `append`.
      #
      # @param [Symbol] attribute_name The event attribute name to read actual time from.
      # @return [void]
      #
      # @example
      #   class SalaryEventStream < Funes::EventStream
      #     actual_time_attribute :effective_date
      #   end
      def actual_time_attribute(attribute_name = nil)
        if attribute_name
          @actual_time_attribute = attribute_name
        else
          @actual_time_attribute
        end
      end

      # Create a new EventStream instance for the given entity identifier.
      #
      # @param [String] idx The entity identifier.
      # @return [Funes::EventStream] A new EventStream instance.
      #
      # @example
      #   stream = OrderEventStream.for("order-123")
      def for(idx)
        new(idx)
      end
    end

    # @!attribute [r] idx
    #   @return [String] The entity identifier for this event stream.
    attr_reader :idx

    # Append a new event to the stream.
    #
    # This method validates the event, resolves the actual time (`occurred_at`), runs the consistency
    # projection (if configured), persists the event with an incremented version number, and triggers
    # transactional and async projections.
    #
    # The `occurred_at` value is resolved via a fallback chain:
    # 1. Explicit `at:` parameter on this method
    # 2. The event's `actual_time_attribute` value (if configured on the stream)
    # 3. Same `Time.current` used for `created_at`
    #
    # `Date` values are coerced to `Time` via `beginning_of_day`.
    #
    # @param [Funes::Event] new_event The event to append to the stream.
    # @param [Time, Date, nil] at The actual time when the event occurred. When provided, this overrides
    #   the event's `actual_time_attribute` value. When nil, falls back to the attribute or `Time.current`.
    # @return [Funes::Event] The event object (check `valid?` to see if it was persisted).
    # @raise [Funes::ConflictingActualTimeError] if both `at:` and the event's `actual_time_attribute`
    #   are present with different values.
    # @raise [Funes::MissingActualTimeAttributeError] if the stream declares `actual_time_attribute`
    #   but the event doesn't have the attribute or its value is nil.
    #
    # @example Successful append
    #   event = stream.append(Order::Placed.new(total: 99.99))
    #   if event.valid?
    #     puts "Event persisted with version #{event.version}"
    #   end
    #
    # @example Append with explicit actual time
    #   event = stream.append(Salary::Raised.new(amount: 6500), at: Time.new(2025, 2, 15))
    #
    # @example Handling validation failure
    #   event = stream.append(InvalidEvent.new)
    #   unless event.valid?
    #     puts "Event rejected: #{event.errors.full_messages}"
    #   end
    #
    # @example Handling concurrency conflict
    #   event = stream.append(SomeEvent.new)
    #   if event.errors[:base].present?
    #     # Race condition detected, retry logic here
    #   end
    def append(new_event, at: nil)
      return new_event unless new_event.valid?

      occurred_at = resolve_proper_occurred_at(new_event, at)

      if consistency_projection.present?
        materialization = compute_projection_with_new_event(consistency_projection, new_event, occurred_at)
        transfer_interpretation_errors(new_event)
        return new_event if materialization.invalid? || new_event.invalid?
      end

      ActiveRecord::Base.transaction do
        begin
          @instance_new_events << new_event.persist!(@idx, incremented_version, at: occurred_at)
          run_transactional_projections
        rescue ActiveRecord::RecordNotUnique
          new_event._event_entry = nil
          new_event.errors.add(:base, I18n.t("funes.events.racing_condition_on_insert"))
          raise ActiveRecord::Rollback
        rescue ActiveRecord::StatementInvalid, ActiveRecord::RecordInvalid => e
          new_event._event_entry = nil
          raise e
        end
      end

      schedule_async_projections unless new_event.errors.any?

      new_event
    end

    # @!visibility private
    def initialize(entity_id)
      @idx = entity_id
      @instance_new_events = []
      @as_of = Time.current
    end

    # Get all events in the stream as event instances.
    #
    # Returns both previously persisted events (up to `as_of` timestamp) and any new events
    # appended in this session, sorted by `occurred_at` ascending.
    #
    # @return [Array<Funes::Event>] Array of event instances ordered by `occurred_at`.
    #
    # @example
    #   stream = OrderEventStream.for("order-123")
    #   stream.events.each do |event|
    #     puts "#{event.class.name} at #{event.created_at}"
    #   end
    def events
      entries = previous_events.to_a + @instance_new_events
      entries.sort_by!(&:occurred_at) if @instance_new_events.any?
      entries.map(&:to_klass_instance)
    end

    # Projects the stream's events using the given projection class.
    #
    # Delegates to the projection's `process_events` class method, passing the stream's
    # events and `as_of` timestamp. When `at:` is provided, events are filtered to only
    # include those where `occurred_at <= at` before projection. When `as_of:` is provided,
    # it overrides the stream's record-time boundary, filtering events in Ruby by `created_at`.
    #
    # @param projection_class [Class<Funes::Projection>] The projection class to use.
    # @param [Time, nil] as_of Optional record-time override. When provided, only events with
    #   `created_at <= as_of` are considered, overriding the stream's own `@as_of`.
    # @param [Time, nil] at Optional actual-time reference. When provided, only events with
    #   `occurred_at <= at` are included in the projection.
    # @return [Object] The materialized state as defined by the projection's materialization model.
    #
    # @example Project current state
    #   stream = OrderEventStream.for("order-123")
    #   snapshot = stream.projected_with(OrderSummaryProjection)
    #   snapshot.total # => 150.0
    #
    # @example Project with actual-time filter
    #   stream = SalaryEventStream.for("sally-123")
    #   snapshot = stream.projected_with(SalaryProjection, at: Time.new(2025, 2, 20))
    #   snapshot.salary # => only reflects events that actually occurred by Feb 20
    #
    # @example Full bitemporal query combining both dimensions in a single call
    #   stream = SalaryEventStream.for("sally-123")
    #   snapshot = stream.projected_with(SalaryProjection,
    #                                    as_of: Time.new(2025, 3, 1),
    #                                    at: Time.new(2025, 2, 20))
    def projected_with(projection_class, as_of: nil, at: nil)
      source_events = as_of ? filter_by_record_time(events, as_of) : events
      target_events = at ? filter_by_actual_time(source_events, at) : source_events
      projection_class.process_events(target_events, at: at)
    end

    # Returns the parameter representation of the event stream for use in URLs.
    #
    # This method follows the ActiveRecord convention for URL generation, allowing EventStream
    # instances to be used directly with Rails URL helpers like `url_for` or named route helpers.
    #
    # @return [String] The entity identifier (`idx`) used as the URL parameter.
    #
    # @example Using with Rails URL helpers
    #   stream = OrderEventStream.for("order-123")
    #   url_for(stream) # => uses "order-123" as the :id parameter
    #
    # @example In path helpers
    #   stream = OrderEventStream.for("order-123")
    #   order_path(stream) # => "/orders/order-123"
    def to_param
      idx
    end

    private
      def run_transactional_projections
        transactional_projections.each do |projection_class|
          Funes::PersistProjectionJob.perform_now(@idx, projection_class, last_event_creation_date,
                                                  last_event_occurrence_date)
        end
      end

      def schedule_async_projections
        async_projections.each do |projection|
          Funes::PersistProjectionJob
            .set(projection[:options])
            .perform_later(@idx, projection[:class], nil,
                           resolve_temporal_context(projection[:temporal_context]))
        end
      end

      def previous_events
        @previous_events ||= Funes::EventEntry
                               .where(idx: @idx, created_at: ..@as_of)
                               .order(:occurred_at)
      end

      def last_event
        (@instance_new_events.last || previous_events.last)
      end

      def last_event_creation_date
        last_event.created_at
      end

      def last_event_occurrence_date
        last_event.occurred_at
      end

      def resolve_temporal_context(strategy)
        last_event = @instance_new_events.last || previous_events.last

        case strategy
        when :last_event_time
          last_event.created_at
        when :job_time
          nil  # Job will use Time.current
        when Proc
          result = strategy.call(last_event)
          unless result.is_a?(Time)
            raise ArgumentError, "Proc must return a Time object, got #{result.class}. " \
                                 "Use :job_time symbol for job execution time behavior."
          end
          result
        else
          raise ArgumentError, "Invalid temporal_context strategy: #{strategy.inspect}. " \
                               "Expected :last_event_time, :job_time, or a Proc"
        end
      end

      def resolve_proper_occurred_at(event, at)
        at_from_param = normalize_at(at)
        at_from_configured_event_attr = actual_time_from_attribute(event)

        if at_from_param && at_from_configured_event_attr && at_from_param != at_from_configured_event_attr
          raise Funes::ConflictingActualTimeError,
                "at: #{at_from_param} conflicts with event.#{self.class.actual_time_attribute}: " \
                "#{at_from_configured_event_attr}"
        end

        at_from_param || at_from_configured_event_attr
      end

      def normalize_at(at)
        return nil unless at
        at.is_a?(Date) && !at.is_a?(Time) ? at.beginning_of_day : at
      end

      def actual_time_from_attribute(event)
        attr_name = self.class.actual_time_attribute
        return nil unless attr_name

        unless event.respond_to?(attr_name)
          raise Funes::MissingActualTimeAttributeError,
                "#{event.class} does not have attribute :#{attr_name} configured as actual_time_attribute on #{self.class}"
        end

        value = event.send(attr_name)

        if value.nil?
          raise Funes::MissingActualTimeAttributeError,
                "#{event.class}##{attr_name} is nil but is configured as actual_time_attribute on #{self.class}"
        end

        value.is_a?(Date) && !value.is_a?(Time) ? value.beginning_of_day : value
      end

      def filter_by_record_time(events_list, as_of)
        events_list.select { |event| event.created_at <= as_of }
      end

      def filter_by_actual_time(events_list, at)
        events_list.select do |event|
          event.occurred_at <= at
        end
      end

      def incremented_version
        max_previous = previous_events.maximum(:version)
        max_new = @instance_new_events.map(&:version).max
        ([ max_previous, max_new ].compact.max || 0) + 1
      end

      def transfer_interpretation_errors(event)
        errors = event.send(:base_errors)
        return if errors.empty?

        errors.each do |error|
          event._interpretation_errors.add(error.attribute, error.message)
        end
        errors.clear
      end

      def compute_projection_with_new_event(projection_class, new_event, at)
        materialization = projection_class.process_events(events + [ new_event ], at: at, consistency: true)
        unless materialization.valid?
          new_event._adjacent_state_errors = materialization.errors
        end

        materialization
      end

      def consistency_projection
        self.class.instance_variable_get(:@consistency_projection) || nil
      end

      def transactional_projections
        self.class.instance_variable_get(:@transactional_projections) || []
      end

      def async_projections
        self.class.instance_variable_get(:@async_projections) || []
      end
  end
end
