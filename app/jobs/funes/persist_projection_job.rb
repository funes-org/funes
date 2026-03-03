module Funes
  class PersistProjectionJob < ApplicationJob
    def perform(event_stream_idx, projection_class, as_of = nil, at = nil)
      event_stream = EventStream.for(event_stream_idx)
      events = as_of ? event_stream.events.select { |e| e.created_at <= as_of } : event_stream.events
      projection_class.materialize!(events, event_stream.idx, as_of, at: at)
    end
  end
end
