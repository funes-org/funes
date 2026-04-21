module Funes
  class PersistProjectionJob < ApplicationJob
    self.enqueue_after_transaction_commit = true

    def perform(event_stream, projection_class, as_of = nil, at = nil)
      events = as_of ? event_stream.events.select { |e| e.created_at <= as_of } : event_stream.events
      projection_class.materialize!(events, event_stream.idx, at: at)
    end
  end
end
