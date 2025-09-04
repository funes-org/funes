module Funes
  class EventEntry < ApplicationRecord
    self.table_name = "event_entries"

    def to_klass_instance
      klass.constantize.new(props.symbolize_keys)
    end
  end
end
