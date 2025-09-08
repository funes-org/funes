module Funes
  module ProjectionTestHelper
    def project_event_based_on(projection_class, event_instance, previous_state)
      projection_class.interpretations[event_instance[:type]]
                      .call(previous_state, event_instance)
    end
  end
end
