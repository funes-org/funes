module Funes
  class Projection
    extend FunctionsManagement
    extend MaterializationManagement
    extend UnknownEventTolerance

    @initial_state = nil

    def self.process_events(events_collection)
      events_collection.inject(@initial_state) do |previous_state, event|
        function = interpretations[event.class]
        if function.nil? && throws_on_unknown_events?
          raise Funes::UnknownEvent, "Events of the type #{event.class} are not processable"
        end

        function.nil? ? previous_state : function.call(previous_state, event)
      end
    end

    # This is probably private API
    def self.materialize!(events_collection, idx)
      raise Funes::UnknownMaterializationModel,
            "There is no materialization model configured on #{name}" unless materialization_model.present?

      pre_persisted_state = valid_attributes_on(process_events(events_collection).merge(idx:))
      materialized_instance = materialized_instance_based_on(pre_persisted_state)
      persist_based_on!(pre_persisted_state) if persistable?

      materialized_instance
    end
  end
end
