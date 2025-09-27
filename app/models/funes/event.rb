module Funes
  class Event
    include ActiveModel::Model
    include ActiveModel::Attributes

    def persist!(idx, version)
      Funes::EventEntry.create!(klass: self.class.name, idx:, version:, props: attributes)
    end

    def inspect
      "<#{self.class.name}: #{attributes}>"
    end
  end
end
