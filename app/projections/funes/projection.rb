require "funes/unknown_event"
require "funes/unknown_materialization_model"

module Funes
  # Projections perform the necessary pattern-matching to compute and aggregate the interpretations that the system
  # gives to a particular collection of events. A projection consists of a series of interpretations defined by the
  # programmer and an aggregated representation of these interpretations (therefore, a representation of transient
  # and final states) which is referenced as the *materialized representation*.
  #
  # A projection can be *virtual* or *persistent*. In practical terms, what defines this characteristic is the type
  # of *materialized representation* configured in the projection.
  #
  # - **Virtual projection:** has an ActiveModel instance as its materialized representation. An instance like this
  # is not persistent, but can be calculated at runtime and has characteristics like validation that are quite
  # valuable in the context of a projection.
  #
  # - **Persistent projection:** has an ActiveRecord instance as its materialized representation. A persistent
  # projection has the same validation capabilities but can be persisted and serve the search patterns needed for
  # the application (read model or even [eager read derivation](https://martinfowler.com/bliki/EagerReadDerivation.html)).
  #
  # ## Temporal Queries with `as_of`
  #
  # The `as_of` parameter enables temporal queries by allowing projections to be computed as they would have been
  # at a specific point in time. When processing events, only events created before or at the `as_of` timestamp
  # are included, enabling point-in-time snapshots of the system state.
  #
  # All interpretation blocks (`initial_state`, `interpretation_for`, and `final_state`) receive the `as_of` parameter,
  # allowing custom temporal logic within projections.
  class Projection
    class << self
      # Registers an interpretation block for a given event type.
      #
      # Inside interpretation blocks, you can reject events by calling +event.errors.add(...)+ on the
      # event. When used as a **consistency projection**, these errors will be transferred to
      # +event.interpretation_errors+ and the event will not be persisted. In transactional or async
      # projections, errors added to the event have no rejection effect and will be logged as a warning.
      #
      # @param [Class<Funes::Event>] event_type The event class constant that will be interpreted.
      # @yield [state, event, as_of] Block invoked with the current state, the event and the as_of marker. It should return a new version of the transient state
      # @yieldparam [ActiveModel::Model, ActiveRecord::Base] transient_state The current transient state
      # @yieldparam [Funes::Event] event Event instance.
      # @yieldparam [Time] as_of Context or timestamp used when interpreting.
      # @yieldreturn [ActiveModel::Model, ActiveRecord::Base] the new transient state
      # @return [void]
      #
      # @example Rejecting an event in a consistency projection
      #   class YourProjection < Funes::Projection
      #     interpretation_for Order::Placed do |transient_state, current_event, _as_of|
      #       current_event.errors.add(:base, "Order total too high") if current_event.amount > 10_000
      #       transient_state.assign_attributes(total: (transient_state.total || 0) + current_event.amount)
      #       transient_state
      #     end
      #   end
      def interpretation_for(event_type, &block)
        @interpretations ||= {}
        @interpretations[event_type] = block
      end

      # Registers the initial transient state that will be used for the current projection's interpretations.
      #
      # *Default behavior:* When no block is provided the initial state defaults to a new instance of
      # the configured materialization model.
      #
      # @yield [materialization_model, as_of] Block invoked to produce the initial state.
      # @yieldparam [Class<ActiveRecord::Base>, Class<ActiveModel::Model>] materialization_model The materialization model constant.
      # @yieldparam [Time] as_of Context or timestamp used when interpreting.
      # @yieldreturn [ActiveModel::Model, ActiveRecord::Base] the new transient state
      # @return [void]
      #
      # @example
      #   class YourProjection < Funes::Projection
      #     initial_state do |materialization_model, _as_of|
      #       materialization_model.new(some: :specific, value: 42)
      #     end
      #   end
      def initial_state(&block)
        @interpretations ||= {}
        @interpretations[:init] = block
      end

      # Register a final interpretation of the state.
      #
      # *Default behavior:* when this is not defined the projection does nothing after the interpretations
      #
      # @yield [transient_state, as_of] Block invoked to produce the final state.
      # @yieldparam [ActiveModel::Model, ActiveRecord::Base] transient_state The current transient state after all interpretations.
      # @yieldparam [Time] as_of Context or timestamp used when interpreting.
      # @yieldreturn [ActiveModel::Model, ActiveRecord::Base] the final transient state instance
      # @return [void]
      #
      # @example
      #   class YourProjection < Funes::Projection
      #     final_state do |transient_state, as_of|
      #       # TODO...
      #     end
      #   end
      def final_state(&block)
        @interpretations ||= {}
        @interpretations[:final] = block
      end

      # Register the projection's materialization model
      #
      # @param [Class<ActiveRecord::Base>, Class<ActiveModel::Model>] active_record_or_model The materialization model class.
      # @return [void]
      #
      # @example Virtual projection (non-persistent, ActiveModel)
      #   class YourProjection < Funes::Projection
      #     materialization_model YourActiveModelClass
      #   end
      #
      # @example Persistent projection (persisted read model, ActiveRecord)
      #   class YourProjection < Funes::Projection
      #     materialization_model YourActiveRecordClass
      #   end
      def materialization_model(active_record_or_model)
        @materialization_model = active_record_or_model
      end

      # It changes the sensibility of the projection about events that it doesn't know how to interpret
      #
      # By default, a projection ignores events that it doesn't have interpretations for. This method informs the
      # projection that in cases like that an Funes::UnknownEvent should be raised and the DB transaction should be
      # rolled back.
      #
      # @return [void]
      #
      # @example
      #   class YourProjection < Funes::Projection
      #     raise_on_unknown_events
      #   end
      def raise_on_unknown_events
        @throws_on_unknown_events = true
      end

      # @!visibility private
      def process_events(events_collection, as_of, at: nil, consistency: false)
        new(self.instance_variable_get(:@interpretations),
            self.instance_variable_get(:@materialization_model),
            self.instance_variable_get(:@throws_on_unknown_events))
          .process_events(events_collection, as_of, at: at, consistency: consistency)
      end

      # @!visibility private
      def materialize!(events_collection, idx, as_of, at: nil)
        new(self.instance_variable_get(:@interpretations),
            self.instance_variable_get(:@materialization_model),
            self.instance_variable_get(:@throws_on_unknown_events))
          .materialize!(events_collection, idx, as_of, at: at)
      end
    end

    # @!visibility private
    def initialize(interpretations, materialization_model, throws_on_unknown_events)
      @interpretations = interpretations
      @materialization_model = materialization_model
      @throws_on_unknown_events = throws_on_unknown_events
    end

    # @!visibility private
    def process_events(events_collection, as_of, at: nil, consistency: false)
      initial_state = interpretations[:init].present? ? interpretations[:init].call(@materialization_model, at) : @materialization_model.new
      state = events_collection.inject(initial_state) do |previous_state, event|
        fn = @interpretations[event.class]
        if fn.nil? && throws_on_unknown_events?
          raise Funes::UnknownEvent, "Events of the type #{event.class} are not processable"
        end

        result = fn.nil? ? previous_state : fn.call(previous_state, event, at)

        warn_about_ineffective_errors(event) unless consistency

        result
      end

      state = interpretations[:final].call(state, at) if interpretations[:final].present?
      state
    end

    # @!visibility private
    def materialize!(events_collection, idx, as_of, at: nil)
      raise Funes::UnknownMaterializationModel,
            "There is no materialization model configured on #{self.class.name}" unless @materialization_model.present?

      state = process_events(events_collection, as_of, at: at)
      materialized_model_instance = materialized_model_instance_based_on(state)
      if materialization_model_is_persistable?
        state.assign_attributes(idx:)
        persist_based_on!(state)
      end

      materialized_model_instance
    end

    private
      def throws_on_unknown_events?
        @throws_on_unknown_events || false
      end

      def interpretations
        @interpretations || {}
      end

      def materialized_model_instance_based_on(state)
        @materialization_model.new(state.attributes)
      end

      def materialization_model_is_persistable?
        @materialization_model.present? && @materialization_model <= ActiveRecord::Base
      end

      def persist_based_on!(state)
        @materialization_model.upsert(state.attributes, unique_by: :idx)
      end

      def warn_about_ineffective_errors(event)
        return unless event.is_a?(Funes::Event)

        base_errors = event.send(:base_errors)
        return if base_errors.empty?

        Rails.logger.warn("[Funes] Errors added to #{event.class} in a non-consistency projection " \
                          "have no effect and will be discarded: #{base_errors.full_messages.join(', ')}")
      end
  end
end
