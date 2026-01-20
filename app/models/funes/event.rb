module Funes
  # Base class for all events in the Funes event sourcing framework.
  #
  # Events are immutable facts that represent something that happened in the system. They use
  # ActiveModel for attributes and validations, making them familiar to Rails developers.
  #
  # ## Event Validation
  #
  # Events support two types of validation:
  #
  # - **Own validation:** Standard ActiveModel validations defined on the event class itself.
  # - **Adjacent state validation:** Validation errors from consistency projections that check
  #   if the event would lead to an invalid state.
  #
  # The `valid?` method returns `true` only if both validations pass. The `errors` method
  # merges both types of errors for display.
  #
  # ## Defining Events
  #
  # Events inherit from `Funes::Event` and define attributes using ActiveModel::Attributes:
  #
  # @example Define a simple event
  #   class Order::Placed < Funes::Event
  #     attribute :total, :decimal
  #     attribute :customer_id, :string
  #     attribute :at, :datetime, default: -> { Time.current }
  #
  #     validates :total, presence: true, numericality: { greater_than: 0 }
  #     validates :customer_id, presence: true
  #   end
  #
  # @example Using the event
  #   event = Order::Placed.new(total: 99.99, customer_id: "cust-123")
  #   stream.append(event)
  #
  # @example Handling validation errors
  #   event = stream.append(Order::Placed.new(total: -10))
  #   unless event.valid?
  #     puts event.own_errors.full_messages      # => Event's own validation errors
  #     puts event.state_errors.full_messages    # => Consistency projection errors
  #     puts event.errors.full_messages          # => All errors merged
  #   end
  class Event
    include ActiveModel::Model
    include ActiveModel::Attributes

    # @!attribute [rw] adjacent_state_errors
    #   @return [ActiveModel::Errors] Validation errors from consistency projections.
    attr_accessor :adjacent_state_errors

    # @!attribute [rw] event_errors
    #   @return [ActiveModel::Errors, nil] The event's own validation errors (internal use).
    attr_accessor :event_errors

    # @!attribute [rw] _event_entry
    #   @return [Funes::EventEntry, nil] The persisted EventEntry record (internal use).
    attr_accessor :_event_entry

    # @!visibility private
    def initialize(*args, **kwargs)
      super(*args, **kwargs)
      @adjacent_state_errors = ActiveModel::Errors.new(nil)
    end

    # @!visibility private
    def persist!(idx, version)
      raise Funes::InvalidEventMetainformation,
            Funes::EventMetainformation.errors.full_messages.join(", ") unless Funes::EventMetainformation.valid?

      self._event_entry = Funes::EventEntry.create!(klass: self.class.name, idx:, version:, props: attributes,
                                                    meta_info: Funes::EventMetainformation.attributes)
    end

    # Check if the event has been persisted to the database.
    #
    # An event is considered persisted if it was either saved via `EventStream#append` or
    # reconstructed from an {EventEntry} via `to_klass_instance`.
    #
    # @return [Boolean] `true` if the event has been persisted, `false` otherwise.
    #
    # @example
    #   event = Order::Placed.new(total: 99.99)
    #   event.persisted?  # => false
    #
    #   stream.append(event)
    #   event.persisted?  # => true (if no validation errors)
    def persisted?
      _event_entry.present?
    end

    # Custom string representation of the event.
    #
    # @return [String] A string showing the event class name and attributes.
    #
    # @example
    #   event = Order::Placed.new(total: 99.99)
    #   event.inspect  # => "<Order::Placed: {:total=>99.99}>"
    def inspect
      "<#{self.class.name}: #{attributes}>"
    end

    # Check if the event is valid.
    #
    # An event is valid only if both its own validations pass AND it doesn't lead to an
    # invalid state (no adjacent_state_errors from consistency projections).
    #
    # @return [Boolean] `true` if the event is valid, `false` otherwise.
    #
    # @example
    #   event = Order::Placed.new(total: 99.99, customer_id: "cust-123")
    #   event.valid?  # => true or false
    def valid?
      super && (adjacent_state_errors.nil? || adjacent_state_errors.empty?)
    end

    # Get validation errors from consistency projections.
    #
    # These are errors that indicate the event would lead to an invalid state, even if
    # the event itself is valid.
    #
    # @return [ActiveModel::Errors] Errors from consistency projection validation.
    #
    # @example
    #   event = stream.append(Inventory::ItemShipped.new(quantity: 9999))
    #   event.state_errors.full_messages  # => ["Quantity on hand must be >= 0"]
    def state_errors
      adjacent_state_errors
    end

    # Get the event's own validation errors (excluding state errors).
    #
    # @return [ActiveModel::Errors] Only the event's own validation errors.
    #
    # @example
    #   event = Order::Placed.new(total: -10)
    #   event.own_errors.full_messages  # => ["Total must be greater than 0"]
    def own_errors
      event_errors || errors
    end

    # Get all validation errors (both event and state errors merged).
    #
    # This method merges the event's own validation errors with any errors from consistency
    # projections, prefixing state errors with a localized message.
    #
    # @return [ActiveModel::Errors] All validation errors combined.
    #
    # @example
    #   event.errors.full_messages
    #   # => ["Total must be greater than 0", "Led to invalid state: Quantity on hand must be >= 0"]
    def errors
      return super if @event_errors.nil?

      tmp_errors = ActiveModel::Errors.new(nil)
      tmp_errors.merge!(event_errors)
      adjacent_state_errors.each do |error|
        tmp_errors.add(:base, "#{I18n.t("funes.events.led_to_invalid_state_prefix")}: #{error.full_message}")
      end
      tmp_errors
    end
  end
end
