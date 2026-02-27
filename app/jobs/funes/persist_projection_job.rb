module Funes
  class PersistProjectionJob < ApplicationJob
    def perform(event_stream_idx, projection_class, as_of = nil, at = nil)
      event_stream = EventStream.for(event_stream_idx, as_of)
      projection_class.materialize!(event_stream.events, event_stream.idx, as_of, at: at)
    end
  end
end
