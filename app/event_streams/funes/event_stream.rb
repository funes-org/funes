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
  # ## Idempotency Keys
  #
  # `append` and `append!` accept an `idempotency_key:`, an arbitrary string composed by the caller
  # that identifies a delivery (a broker message, a form submission), not a domain fact. The key is
  # stored with the event and a unique constraint on `idempotency_key` guarantees that it is used
  # at most once across all streams, even under concurrent appends. A key that names a fact of one
  # entity must therefore carry the entity, e.g. `"fee:#{idx}:2026-02"`.
  #
  # When the key is already stored:
  #
  # - In the same stream, by an event with the same class and attributes (metainformation is
  #   ignored): the append is a duplicate. Nothing is written, no projection runs, and the event is
  #   returned carrying the original entry, with `duplicate?` returning true.
  # - In the same stream, by an event with a different class or attributes: the append is a
  #   conflict. `append` returns the event unpersisted with an error; `append!` raises
  #   {Funes::IdempotencyKeyConflictError}.
  # - In another stream: the caller is on the wrong stream, whatever the event looks like. `append`
  #   returns the event unpersisted with an error that names that stream; `append!` raises
  #   {Funes::IdempotencyKeyUsedInAnotherStreamError}, whose `idx` names it. This is what a
  #   redelivered creation message hits when the consumer mints a new `idx` for each delivery.
  #
  # Streams can declare which events must arrive with a key via `requires_idempotency_key` (every
  # event) or `requires_idempotency_key_for` (some event classes); a missing required key raises
  # {Funes::MissingIdempotencyKeyError}.
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
    # Raised inside the append transaction when the database rejects a row for a unique index, so
    # the block rolls back and the caller decides, outside the transaction, whether the collision was
    # a repeated idempotency key or a version race.
    class UniquenessViolation < StandardError
      attr_reader :on_insert

      def initialize(on_insert:)
        super("unique index violated while appending an event")
        @on_insert = on_insert
      end
    end
    private_constant :UniquenessViolation

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

      # Requires an idempotency key for every event appended to this stream.
      #
      # Appending without `idempotency_key:` raises {Funes::MissingIdempotencyKeyError}, on both
      # `append` and `append!`.
      #
      # @return [void]
      #
      # @example
      #   class LedgerEventStream < Funes::EventStream
      #     requires_idempotency_key
      #   end
      def requires_idempotency_key
        @requires_idempotency_key = true
      end

      # Requires an idempotency key only for the given event classes.
      #
      # Appending one of these events (or an instance of a subclass) without `idempotency_key:`
      # raises {Funes::MissingIdempotencyKeyError}, on both `append` and `append!`. Other events
      # can still be appended without a key.
      #
      # @param [Array<Class<Funes::Event>>] event_classes The event classes that need a key.
      #   An array is accepted too.
      # @return [void]
      #
      # @example
      #   class DebtEventStream < Funes::EventStream
      #     requires_idempotency_key_for Debt::FeeCharged, Debt::PaymentReceived
      #   end
      def requires_idempotency_key_for(*event_classes)
        @idempotency_key_required_for ||= []
        @idempotency_key_required_for.concat(event_classes.flatten)
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
    # Event-level failures are quiet, mirroring `ActiveRecord::Base#save`: when the event's own
    # validation fails, the consistency projection rejects the event, or a version conflict occurs
    # (race condition on insert), `append` raises nothing — it returns the event unpersisted with
    # its errors populated.
    #
    # When `idempotency_key:` is given and the key is already stored, nothing is written and no
    # projection runs. If the stored event is in this stream with the same class and attributes,
    # the event is returned with `duplicate?` true, carrying the original entry (`persisted?` is
    # true and `version` is the original one). Otherwise the key conflicts, either with a different
    # event in this stream or with an event in another stream: the event is returned unpersisted
    # with an error on `errors[:base]`.
    #
    # A transactional projection failure is loud even on this non-bang form: the exception escapes
    # the call untouched and the transaction rolls back, so the event never lands in the log
    # (`event.persisted?` is false after the rescue). The caller must rescue these exceptions;
    # the quiet contract of `append` covers only the event-level failures above.
    #
    # @param [Funes::Event] new_event The event to append to the stream.
    # @param [Time, Date, nil] at The actual time when the event occurred. When provided, this overrides
    #   the event's `actual_time_attribute` value. When nil, falls back to the attribute or `Time.current`.
    # @param [String, nil] idempotency_key A caller-composed string that identifies this delivery.
    #   Unique across all streams. A blank value counts as no key.
    # @return [Funes::Event] The event object (check `persisted?` or `valid?` to see if it was persisted).
    # @raise [ActiveRecord::RecordInvalid] if a transactional projection's materialization fails its
    #   validations on the default upsert path. `e.record` is the projection's materialization model,
    #   not the event.
    # @raise [ActiveRecord::StatementInvalid] if a transactional projection fails with a database
    #   error, such as a constraint violation.
    # @raise [Funes::InvalidMaterializationState] if a transactional projection that persists via
    #   `persist_materialization_model_with` produces an invalid state. `e.record` is the
    #   materialization model.
    # @raise [Funes::UnknownEvent] if a consistency or transactional projection in strict mode
    #   receives an event without an `interpretation_for` block.
    # @raise [Funes::ConflictingActualTimeError] if both `at:` and the event's `actual_time_attribute`
    #   are present with different values.
    # @raise [Funes::MissingActualTimeAttributeError] if the stream declares `actual_time_attribute`
    #   but the event doesn't have the attribute or its value is nil.
    # @raise [Funes::MissingIdempotencyKeyError] if the stream requires an idempotency key for the
    #   event (`requires_idempotency_key` / `requires_idempotency_key_for`) and none was given.
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
    #
    # @example Append with an idempotency key
    #   event = stream.append(Debt::PaymentReceived.new(amount: 30), idempotency_key: "charge:ch_1")
    #   event.duplicate? # => true when "charge:ch_1" already recorded this same payment
    def append(new_event, at: nil, idempotency_key: nil)
      do_append(new_event, at: at, idempotency_key: idempotency_key, raise_on_failure: false)
    end

    # Append a new event to the stream, raising on any failure.
    #
    # Behaves like {#append}, but raises `ActiveRecord::RecordInvalid` whenever the event cannot be
    # persisted — mirroring the relationship between `ActiveRecord::Base#save` and `#save!`. Because
    # a real exception is raised, any enclosing `ActiveRecord::Base.transaction` block rolls back,
    # which is what you want when you need host-managed transactional control around `append`.
    #
    # The failed event is always queryable after the rescue: `event.persisted?` returns false and
    # `event.errors` is populated (for event-level failures such as validation, consistency
    # rejection, or version conflict).
    #
    # Failure modes:
    # - Event's own validation fails → raises `ActiveRecord::RecordInvalid` with the event as `record`.
    # - Consistency projection rejects the event → raises `ActiveRecord::RecordInvalid` with the
    #   event as `record` (state / interpretation errors transferred to the event).
    # - Version conflict (race condition on insert) → raises `ActiveRecord::RecordInvalid` with the
    #   event as `record` and a racing-condition message on `event.errors[:base]`.
    # - A transactional projection's persistence fails → the original
    #   `ActiveRecord::StatementInvalid` / `ActiveRecord::RecordInvalid` (or
    #   `Funes::InvalidMaterializationState` on a custom persist method) is re-raised untouched (its
    #   `record` is the projection's materialization model, not the event). `event.persisted?` is
    #   still false after the rescue. Plain {#append} raises these too — this failure mode is not
    #   exclusive to the bang form.
    # - The idempotency key is already stored in this stream for a different event class or
    #   different attributes → raises {Funes::IdempotencyKeyConflictError}. A repeated key with the
    #   same class and attributes is not a failure: the event is returned with `duplicate?` true.
    # - The idempotency key is already stored in another stream → raises
    #   {Funes::IdempotencyKeyUsedInAnotherStreamError}; its `idx` names that stream.
    #
    # Async projections are only enqueued when `append!` returns successfully. When `append!` is
    # nested inside a user-opened `ActiveRecord::Base.transaction` that later rolls back, Rails'
    # `enqueue_after_transaction_commit` discards the deferred enqueue so no job runs.
    #
    # @param [Funes::Event] new_event The event to append to the stream.
    # @param [Time, Date, nil] at See {#append}.
    # @param [String, nil] idempotency_key See {#append}.
    # @return [Funes::Event] The persisted event.
    # @raise [ActiveRecord::RecordInvalid] When the event cannot be persisted. `e.record` is the
    #   failed event (for event-level failures) or a projection materialization model (for
    #   projection validation failures).
    # @raise [ActiveRecord::StatementInvalid] When a transactional projection fails with a database
    #   constraint violation.
    # @raise [Funes::InvalidMaterializationState] When a transactional projection that persists via
    #   `persist_materialization_model_with` produces an invalid state. See {#append}.
    # @raise [Funes::UnknownEvent] When a projection in strict mode receives an event without an
    #   `interpretation_for` block. See {#append}.
    # @raise [Funes::ConflictingActualTimeError] See {#append}.
    # @raise [Funes::MissingActualTimeAttributeError] See {#append}.
    # @raise [Funes::MissingIdempotencyKeyError] See {#append}.
    # @raise [Funes::IdempotencyKeyConflictError] When the idempotency key is already stored in this
    #   stream for a different event class or different attributes.
    # @raise [Funes::IdempotencyKeyUsedInAnotherStreamError] When the idempotency key is already
    #   stored in another stream. A subclass of {Funes::IdempotencyKeyConflictError}.
    #
    # @example Host-managed transaction with a sibling AR update
    #   event = SomeEvent.new(some: "value")
    #   begin
    #     ActiveRecord::Base.transaction do
    #       some_model.update!(some: "value")
    #       SomeEventStream.for(stream_id).append!(event)
    #     end
    #   rescue ActiveRecord::RecordInvalid
    #     event.persisted?  # => false
    #     event.errors.any? # => true
    #   end
    #
    # @example Two appends in a single transaction — either both commit or neither does
    #   event_1 = SomeEvent.new(some: "value")
    #   event_2 = OtherEvent.new(some: "value")
    #   begin
    #     ActiveRecord::Base.transaction do
    #       SomeEventStream.for(stream_id).append!(event_1)
    #       OtherEventStream.for(other_stream_id).append!(event_2)
    #     end
    #   rescue ActiveRecord::RecordInvalid
    #     event_1.persisted? # => false
    #     event_2.persisted? # => false
    #   end
    def append!(new_event, at: nil, idempotency_key: nil)
      do_append(new_event, at: at, idempotency_key: idempotency_key, raise_on_failure: true)
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
    # Mirrors `ActiveRecord::Base.find`: if there are no events to replay — either because the
    # stream has no events at all or because `as_of:` / `at:` filtering leaves none in scope —
    # raises {ActiveRecord::RecordNotFound}. In a Rails controller, this lets the host app's
    # middleware render a 404 automatically, without any rescue wiring.
    #
    # @param projection_class [Class<Funes::Projection>] The projection class to use.
    # @param [Time, nil] as_of Optional record-time override. When provided, only events with
    #   `created_at <= as_of` are considered, overriding the stream's own `@as_of`.
    # @param [Time, nil] at Optional actual-time reference. When provided, only events with
    #   `occurred_at <= at` are included in the projection.
    # @return [Object] The materialized state as defined by the projection's materialization model.
    # @raise [ActiveRecord::RecordNotFound] when the filtered event list is empty — either
    #   because the stream has no events or because `as_of:` / `at:` excludes them all.
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
    #
    # @example Automatic 404 in a Rails controller
    #   class OrdersController < ApplicationController
    #     def show
    #       stream = OrderEventStream.for(params[:id])
    #       @order = stream.projected_with(OrderSummaryProjection)
    #     end
    #   end
    #   # If no events exist for params[:id], Rails renders its 404 page automatically.
    def projected_with(projection_class, as_of: nil, at: nil)
      source_events = as_of ? filter_by_record_time(events, as_of) : events
      target_events = at ? filter_by_actual_time(source_events, at) : source_events

      if target_events.empty?
        materialization_model = projection_class.instance_variable_get(:@materialization_model)
        model_name = materialization_model&.name
        Rails.logger.info(
          "[Funes] projected_with found no events for " \
          "#{self.class.name} idx=#{idx.inspect} " \
          "projection=#{projection_class.name} " \
          "as_of=#{as_of.inspect} at=#{at.inspect}"
        )
        raise ActiveRecord::RecordNotFound.new(
          "Couldn't find #{model_name} for #{self.class.name} #{idx.inspect}",
          model_name,
          "idx",
          idx
        )
      end

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
      def do_append(new_event, at:, idempotency_key:, raise_on_failure:)
        idempotency_key = resolve_idempotency_key(new_event, idempotency_key)

        unless new_event.valid?
          raise ActiveRecord::RecordInvalid.new(new_event) if raise_on_failure
          return new_event
        end

        occurred_at = resolve_proper_occurred_at(new_event, at)

        # Fast path only: the unique index on idempotency_key is the guarantee.
        if idempotency_key && (stored_entry = entry_with_idempotency_key(idempotency_key))
          return resolve_repeated_idempotency_key(new_event, stored_entry, raise_on_failure:)
        end

        if consistency_projection.present?
          materialization = compute_projection_with_new_event(consistency_projection, new_event, occurred_at)
          transfer_interpretation_errors(new_event)
          if materialization.invalid? || new_event.invalid?
            raise ActiveRecord::RecordInvalid.new(new_event) if raise_on_failure
            return new_event
          end
        end

        begin
          persist_with_transactional_projections(new_event, occurred_at, idempotency_key)
        rescue UniquenessViolation => violation
          return resolve_uniqueness_violation(new_event, idempotency_key, violation, raise_on_failure:)
        end

        schedule_async_projections

        new_event
      end

      def persist_with_transactional_projections(new_event, occurred_at, idempotency_key)
        ActiveRecord::Base.transaction do
          begin
            @instance_new_events << new_event.persist!(@idx, incremented_version, at: occurred_at,
                                                       idempotency_key: idempotency_key)
            ActiveRecord::Base.connection.current_transaction.after_rollback do
              new_event._event_entry = nil
            end
            run_transactional_projections
          rescue ActiveRecord::RecordNotUnique
            # persist! sets the entry only when its INSERT succeeded; a violation with the entry in
            # place came from a transactional projection.
            on_insert = !new_event.persisted?
            new_event._event_entry = nil
            raise UniquenessViolation.new(on_insert: on_insert)
          rescue ActiveRecord::StatementInvalid, ActiveRecord::RecordInvalid => e
            new_event._event_entry = nil
            raise e
          end
        end
      end

      # The violation can come from (idx, version) or from idempotency_key, and the database
      # exception does not tell which. A stored entry with the same key answers it. The lookup runs
      # here, outside the transaction block, because on PostgreSQL the failed insert aborts the
      # transaction and any query inside it would error.
      def resolve_uniqueness_violation(new_event, idempotency_key, violation, raise_on_failure:)
        if idempotency_key && violation.on_insert &&
           (stored_entry = entry_with_idempotency_key_after_violation(idempotency_key))
          return resolve_repeated_idempotency_key(new_event, stored_entry, raise_on_failure:)
        end

        new_event.errors.add(:base, I18n.t("funes.events.racing_condition_on_insert"))
        raise ActiveRecord::RecordInvalid.new(new_event) if raise_on_failure

        new_event
      end

      def resolve_idempotency_key(event, idempotency_key)
        idempotency_key = idempotency_key.presence&.to_s
        return idempotency_key if idempotency_key || !idempotency_key_required_for?(event)

        raise Funes::MissingIdempotencyKeyError,
              "#{self.class} requires an idempotency key to append #{event.class}, but none was given"
      end

      def idempotency_key_required_for?(event)
        return true if self.class.instance_variable_get(:@requires_idempotency_key)

        (self.class.instance_variable_get(:@idempotency_key_required_for) || [])
          .any? { |event_class| event.is_a?(event_class) }
      end

      def entry_with_idempotency_key(idempotency_key)
        Funes::EventEntry.find_by(idempotency_key: idempotency_key)
      end

      # When the append is nested in a host-opened transaction on PostgreSQL, that transaction is
      # already aborted by the failed insert and the lookup itself errors. The append then falls
      # back to the racing-condition error; a retry in a fresh transaction hits the fast path.
      def entry_with_idempotency_key_after_violation(idempotency_key)
        entry_with_idempotency_key(idempotency_key)
      rescue ActiveRecord::StatementInvalid
        nil
      end

      def resolve_repeated_idempotency_key(new_event, stored_entry, raise_on_failure:)
        if stored_entry.idx != @idx
          new_event.errors.add(:base, I18n.t("funes.events.idempotency_key_used_in_another_stream",
                                             idx: stored_entry.idx))
          if raise_on_failure
            raise Funes::IdempotencyKeyUsedInAnotherStreamError.new(
              "idempotency key #{stored_entry.idempotency_key.inspect} was already used in event " \
              "stream #{stored_entry.idx.inspect} (#{stored_entry.klass}, version #{stored_entry.version})",
              entry: stored_entry
            )
          end
          return new_event
        end

        if same_event?(new_event, stored_entry)
          new_event._event_entry = stored_entry
          new_event._duplicate = true
          return new_event
        end

        new_event.errors.add(:base, I18n.t("funes.events.idempotency_key_conflict"))
        if raise_on_failure
          raise Funes::IdempotencyKeyConflictError.new(
            "idempotency key #{stored_entry.idempotency_key.inspect} was already used in " \
            "#{self.class} #{@idx.inspect} by a different event (#{stored_entry.klass}, " \
            "version #{stored_entry.version})",
            entry: stored_entry
          )
        end

        new_event
      end

      # Compares class and attributes only; metainformation is ignored, so the same fact recorded
      # by two different users is a duplicate. Attributes are compared in their serialized form,
      # the same form the stored props went through.
      def same_event?(new_event, stored_entry)
        stored_entry.klass == new_event.class.name &&
          stored_entry.props == ActiveSupport::JSON.decode(ActiveSupport::JSON.encode(new_event.attributes))
      end

      def run_transactional_projections
        transactional_projections.each do |projection_class|
          Funes::PersistProjectionJob.perform_now(self, projection_class, last_event_creation_date,
                                                  last_event_occurrence_date)
        end
      end

      def schedule_async_projections
        async_projections.each do |projection|
          Funes::PersistProjectionJob
            .set(projection[:options])
            .perform_later(self, projection[:class], nil,
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
