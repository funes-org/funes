module Funes
  class Projection
    class << self
      def interpretation_for(event_type, &block)
        @interpretations ||= {}
        @interpretations[event_type] = block
      end

      def initial_state(&block)
        @interpretations ||= {}
        @interpretations[:init] = block
      end

      def final_state(&block)
        @interpretations ||= {}
        @interpretations[:final] = block
      end

      def materialization_model(active_record_or_model)
        @materialization_model = active_record_or_model
      end

      def raise_on_unknown_events
        @throws_on_unknown_events = true
      end

      def process_events(events_collection, as_of = nil)
        new(self.instance_variable_get(:@interpretations),
            self.instance_variable_get(:@materialization_model),
            self.instance_variable_get(:@throws_on_unknown_events))
          .process_events(events_collection, as_of)
      end

      def materialize!(events_collection, idx, as_of)
        new(self.instance_variable_get(:@interpretations),
            self.instance_variable_get(:@materialization_model),
            self.instance_variable_get(:@throws_on_unknown_events))
          .materialize!(events_collection, idx, as_of)
      end
    end

    def initialize(interpretations, materialization_model, throws_on_unknown_events)
      @interpretations = interpretations
      @materialization_model = materialization_model
      @throws_on_unknown_events = throws_on_unknown_events
    end


    def process_events(events_collection, as_of)
      initial_state = interpretations[:init].present? ? interpretations[:init].call(@materialization_model, as_of) : @materialization_model.new
      state = events_collection.inject(initial_state) do |previous_state, event|
        fn = @interpretations[event.class]
        if fn.nil? && throws_on_unknown_events?
          raise Funes::UnknownEvent, "Events of the type #{event.class} are not processable"
        end

        fn.nil? ? previous_state : fn.call(previous_state, event, as_of)
      end

      state = interpretations[:final].call(state, as_of) if interpretations[:final].present?
      state
    end

    def materialize!(events_collection, idx, as_of)
      raise Funes::UnknownMaterializationModel,
            "There is no materialization model configured on #{self.class.name}" unless @materialization_model.present?

      state = process_events(events_collection, as_of)
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
  end
end
