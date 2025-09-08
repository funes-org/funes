module Funes
  module ProjectionTestHelper
    def apply_event_to_state(projection_class, previous_state, event)
      projection_class.interpretations[event[:type]]
                      .call(previous_state, event)
    end
  end
end
