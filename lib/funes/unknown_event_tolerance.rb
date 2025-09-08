module Funes
  module UnknownEventTolerance
    def throws_on_unknow_events
      @throws_on_unknow_events ||= false
    end

    def throws_on_unknow_events?
      throws_on_unknow_events
    end

    def not_ignore_unknow_event_types
      @throws_on_unknow_events = true
    end
  end
end
