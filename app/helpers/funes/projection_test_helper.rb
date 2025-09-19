module Funes
  module ProjectionTestHelper
    # @TODO add test coverage
    def interpret_event_based_on(projection_class, event_instance, previous_state)
      projection_class.interpretations[event_instance.class]
                      .call(previous_state, event_instance)
    end
  end
end
