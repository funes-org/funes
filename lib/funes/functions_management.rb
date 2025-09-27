module Funes
  module FunctionsManagement
    def interpretations
      @interpretations ||= {}
    end

    def set_interpretation_for(event_type, &block)
      interpretations[event_type] = block
    end

    alias set_function_for set_interpretation_for
    alias functions interpretations

    def set_initial_state(&block)
      interpretations[:init] = block
    end

    def set_wrap_up_function(&block)
      interpretations[:final] = block
    end
  end
end
