module Funes
  class PersistProjectionJob < ApplicationJob
    def perform(event_stream_id, projection_class)
      event_stream = EventStream.with_id(event_stream_id)
      projection_class.materialize!(event_stream.events, event_stream_id)
    end
  end
end
