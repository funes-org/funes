module Funes
  module UnknownEventTolerance
    def throws_on_unknown_events
      @throws_on_unknown_events ||= false
    end

    def throws_on_unknown_events?
      throws_on_unknown_events
    end

    def not_ignore_unknown_event_types
      @throws_on_unknown_events = true
    end
  end
end
