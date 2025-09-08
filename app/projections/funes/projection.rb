module Funes
  class Projection
    extend FunctionsManagement
    extend UnknownEventTolerance

    @initial_state = nil

    def self.process_events(events_collection)
      events_collection.inject(@initial_state) do |previous_state, event|
        function = interpretations[event.class]
        if function.nil? && throws_on_unknow_events?
          raise Funes::UnknownEvent, "Events of the type #{event.class} are not processable"
        end

        function.nil? ? previous_state : function.call(previous_state, event)
      end
    end
  end
end
