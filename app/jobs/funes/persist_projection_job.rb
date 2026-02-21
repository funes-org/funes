module Funes
  class PersistProjectionJob < ApplicationJob
    def perform(event_stream_idx, projection_class, as_of = nil, at = nil)
      event_stream = EventStream.for(event_stream_idx, as_of)
      target_events = at ? event_stream.send(:filter_by_actual_time, event_stream.events, at) : event_stream.events
      projection_class.materialize!(target_events, event_stream.idx, as_of, at: at)
    end
  end
end
