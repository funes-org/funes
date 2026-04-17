module Funes
  class EventStreamSerializer < ActiveJob::Serializers::ObjectSerializer
    def serialize?(argument)
      argument.is_a?(Funes::EventStream)
    end

    def serialize(event_stream)
      super("idx" => event_stream.idx,
            "class" => event_stream.class.name)
    end

    def deserialize(hash)
      hash["class"].constantize.for(hash["idx"])
    end
  end
end
