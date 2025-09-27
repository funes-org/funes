module Funes
  class Projection
    extend FunctionsManagement
    extend MaterializationManagement
    extend UnknownEventTolerance

    def self.process_events(events_collection)
      initial_state = interpretations[:init].present? ? interpretations[:init].call : nil
      state = events_collection.inject(initial_state) do |previous_state, event|
        function = interpretations[event.class]
        if function.nil? && throws_on_unknown_events?
          raise Funes::UnknownEvent, "Events of the type #{event.class} are not processable"
        end

        function.nil? ? previous_state : function.call(previous_state, event)
      end
      state = interpretations[:final].call(state) if interpretations[:final].present?
      state
    end

    # This is probably private API
    def self.materialize!(events_collection, idx)
      raise Funes::UnknownMaterializationModel,
            "There is no materialization model configured on #{name}" unless materialization_model.present?

      # pre_persisted_state = valid_attributes_on(process_events(events_collection).merge(idx:))
      pre_persisted_state = process_events(events_collection)
      materialized_instance = materialized_instance_based_on(pre_persisted_state)
      if persistable?
        pre_persisted_state.assign_attributes(idx:)
        persist_based_on!(pre_persisted_state)
      end

      materialized_instance
    end
  end
end
