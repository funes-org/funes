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
  # ## Temporal Queries
  #
  # EventStreams support temporal queries through the `as_of` parameter. When an EventStream is created
  # with a specific timestamp, only events created before or at that timestamp are included, enabling
  # point-in-time state reconstruction.
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
  # @example Temporal query - get stream state as of a specific time
  #   stream = OrderEventStream.for("order-123", 1.month.ago)
  #   stream.events # => only events up to 1 month ago
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
      # The `as_of` parameter controls the timestamp used when the projection job executes:
      # - `:last_event_time` (default) - Uses the creation time of the last event
      # - `:job_time` - Uses Time.current when the job executes
      # - Proc/Lambda - Custom logic that receives the last event and returns a Time object
      #
      # @param [Class<Funes::Projection>] projection The projection class to execute asynchronously.
      # @param [Symbol, Proc] as_of Strategy for determining the as_of timestamp (:last_event_time, :job_time, or Proc).
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
      #     add_async_projection RealtimeProjection, as_of: :job_time
      #   end
      #
      # @example Custom as_of logic with proc
      #   class OrderEventStream < Funes::EventStream
      #     add_async_projection EndOfDayProjection, as_of: ->(last_event) { last_event.created_at.beginning_of_day }
      #   end
      def add_async_projection(projection, as_of: :last_event_time, **options)
        @async_projections ||= []
        @async_projections << { class: projection, as_of_strategy: as_of, options: options }
      end

      # Create a new EventStream instance for the given entity identifier.
      #
      # @param [String] idx The entity identifier.
      # @param [Time, nil] as_of Optional timestamp for temporal queries. If provided, only events
      #   created before or at this timestamp will be included. Defaults to Time.current.
      # @return [Funes::EventStream] A new EventStream instance.
      #
      # @example Current state
      #   stream = OrderEventStream.for("order-123")
      #
      # @example State as of a specific time
      #   stream = OrderEventStream.for("order-123", 1.month.ago)
      def for(idx, as_of = nil)
        new(idx, as_of)
      end
    end

    # @!attribute [r] idx
    #   @return [String] The entity identifier for this event stream.
    attr_reader :idx

    # Append a new event to the stream.
    #
    # This method validates the event, runs the consistency projection (if configured), persists the event
    # with an incremented version number, and triggers transactional and async projections.
    #
    # @param [Funes::Event] new_event The event to append to the stream.
    # @return [Funes::Event] The event object (check `valid?` to see if it was persisted).
    #
    # @example Successful append
    #   event = stream.append(Order::Placed.new(total: 99.99))
    #   if event.valid?
    #     puts "Event persisted with version #{event.version}"
    #   end
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
    def append(new_event)
      return new_event unless new_event.valid?
      return new_event if consistency_projection.present? &&
                          (compute_projection_with_new_event(consistency_projection, new_event).invalid? ||
                           new_event.invalid?)

      ActiveRecord::Base.transaction do
        begin
          @instance_new_events << new_event.persist!(@idx, incremented_version)
          run_transactional_projections
        rescue ActiveRecord::RecordNotUnique
          new_event._event_entry = nil
          new_event.errors.add(:base, I18n.t("funes.events.racing_condition_on_insert"))
          raise ActiveRecord::Rollback
        rescue ActiveRecord::StatementInvalid => e
          new_event._event_entry = nil
          raise e
        end
      end

      schedule_async_projections unless new_event.errors.any?

      new_event
    end

    # @!visibility private
    def initialize(entity_id, as_of = nil)
      @idx = entity_id
      @instance_new_events = []
      @as_of = as_of ? as_of : Time.current
    end

    # Get all events in the stream as event instances.
    #
    # Returns both previously persisted events (up to `as_of` timestamp) and any new events
    # appended in this session.
    #
    # @return [Array<Funes::Event>] Array of event instances.
    #
    # @example
    #   stream = OrderEventStream.for("order-123")
    #   stream.events.each do |event|
    #     puts "#{event.class.name} at #{event.created_at}"
    #   end
    def events
      (previous_events + @instance_new_events).map(&:to_klass_instance)
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
          Funes::PersistProjectionJob.perform_now(@idx, projection_class, last_event_creation_date)
        end
      end

      def schedule_async_projections
        async_projections.each do |projection|
          as_of = resolve_as_of_strategy(projection[:as_of_strategy])
          Funes::PersistProjectionJob.set(projection[:options]).perform_later(@idx, projection[:class], as_of)
        end
      end

      def previous_events
        @previous_events ||= Funes::EventEntry
                               .where(idx: @idx, created_at: ..@as_of)
                               .order("created_at")
      end

      def last_event_creation_date
        (@instance_new_events.last || previous_events.last).created_at
      end

      def resolve_as_of_strategy(strategy)
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
          raise ArgumentError, "Invalid as_of strategy: #{strategy.inspect}. " \
                               "Expected :last_event_time, :job_time, or a Proc"
        end
      end

      def incremented_version
        (@instance_new_events.last&.version || previous_events.last&.version || 0) + 1
      end

      def compute_projection_with_new_event(projection_class, new_event)
        materialization = projection_class.process_events(events + [ new_event ], @as_of)
        unless materialization.valid?
          new_event.adjacent_state_errors = materialization.errors
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
