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
  end
end
