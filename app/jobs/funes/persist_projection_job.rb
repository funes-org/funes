module Funes
  class PersistProjectionJob < ApplicationJob
    def perform(event_stream_arg, projection_class, as_of = nil)
      event_stream = event_stream_instance(event_stream_arg, as_of)
      projection_class.materialize!(event_stream.events, event_stream.idx)
    end

    private
      def event_stream_instance(event_stream_arg, as_of)
        if event_stream_arg.is_a? Funes::EventStream
          event_stream_arg
        else
          EventStream.with_id(event_stream_arg, as_of)
        end
      end
  end
end
