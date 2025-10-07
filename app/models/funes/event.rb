module Funes
  class Event
    include ActiveModel::Model
    include ActiveModel::Attributes

    attr_accessor :adjacent_state_errors
    attr_accessor :event_errors

    def initialize(*args, **kwargs)
      super(*args, **kwargs)
      @adjacent_state_errors = ActiveModel::Errors.new(nil)
    end

    def persist!(idx, version)
      Funes::EventEntry.create!(klass: self.class.name, idx:, version:, props: attributes)
    end

    def inspect
      "<#{self.class.name}: #{attributes}>"
    end

    def valid?
      super && (adjacent_state_errors.nil? || adjacent_state_errors.empty?)
    end

    # TODO: pensar melhor esse nome
    def state_errors
      adjacent_state_errors
    end

    def own_errors
      event_errors || errors
    end

    def errors
      return super if @event_errors.nil?

      tmp_errors = ActiveModel::Errors.new(nil)
      tmp_errors.merge!(event_errors)
      tmp_errors.merge!(adjacent_state_errors)
      tmp_errors
    end
  end
end
