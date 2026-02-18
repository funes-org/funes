module Funes
  # Base class for all events in the Funes event sourcing framework.
  #
  # Events are immutable facts that represent something that happened in the system. They use
  # ActiveModel for attributes and validations, making them familiar to Rails developers.
  #
  # ## Event Validation
  #
  # Events support three types of validation:
  #
  # - **Own validation:** Standard ActiveModel validations defined on the event class itself.
  # - **Adjacent state validation:** Validation errors from consistency projections that check
  #   if the event would lead to an invalid state.
  # - **Interpretation errors:** Errors added via +event.errors.add(...)+ inside interpretation
  #   blocks. When used in a consistency projection, these are automatically transferred to
  #   +interpretation_errors+ and cause the event to be rejected.
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
    include Funes::Inspection

    # @!attribute [rw] adjacent_state_errors
    #   @return [ActiveModel::Errors] Validation errors from consistency projections.
    attr_accessor :_adjacent_state_errors

    # @!attribute [rw] interpretation_errors
    #   @return [ActiveModel::Errors] Explicit rejection errors from consistency projection interpretation blocks.
    attr_accessor :_interpretation_errors

    # @!attribute [rw] _event_entry
    #   @return [Funes::EventEntry, nil] The persisted EventEntry record (internal use).
    attr_accessor :_event_entry

    # @!visibility private
    def initialize(*args, **kwargs)
      super(*args, **kwargs)
      @_adjacent_state_errors = ActiveModel::Errors.new(self)
      @_interpretation_errors = ActiveModel::Errors.new(self)
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
      super && _adjacent_state_errors.empty? && _interpretation_errors.empty?
    end

    # Check if the event is invalid.
    #
    # An event is invalid if any of its own validations fail, it leads to an invalid state
    # (adjacent_state_errors), or it has been explicitly rejected via interpretation_errors.
    #
    # @return [Boolean] `true` if the event is invalid, `false` otherwise.
    #
    # @example
    #   event = Order::Placed.new(total: -10)
    #   event.invalid?  # => true (own validation failed)
    def invalid? = !valid?

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
      _adjacent_state_errors
    end

    # Get the event's own validation errors (excluding state errors).
    #
    # @return [ActiveModel::Errors] Only the event's own validation errors.
    #
    # @example
    #   event = Order::Placed.new(total: -10)
    #   event.own_errors.full_messages  # => ["Total must be greater than 0"]
    def own_errors
      tmp_errors = ActiveModel::Errors.new(self)
      tmp_errors.merge!(base_errors)
      merge_errors_into(tmp_errors, _interpretation_errors)

      tmp_errors
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
      return super unless !_adjacent_state_errors.empty? || !_interpretation_errors.empty?

      tmp_errors = ActiveModel::Errors.new(self)
      tmp_errors.merge!(super)
      merge_errors_into(tmp_errors, _adjacent_state_errors, state_errors: true)
      merge_errors_into(tmp_errors, _interpretation_errors)

      tmp_errors
    end

    private
      # Get the base ActiveModel validation errors.
      # This method provides access to the validation errors from ActiveModel::Validations,
      # which is the parent implementation of the errors method that we override.
      #
      # @return [ActiveModel::Errors] The ActiveModel validation errors.
      def base_errors
        method(:errors).super_method.call
      end

      # Merge errors from a source collection into a target errors object.
      #
      # @param target_errors [ActiveModel::Errors] The target errors object to merge into
      # @param source_errors [ActiveModel::Errors, nil] The source errors to merge from
      # @param state_errors [Boolean] Whether these are adjacent state errors (applies prefix transform)
      # @return [void]
      def merge_errors_into(target_errors, source_errors, state_errors: false)
        return unless source_errors.present? && !source_errors.empty?

        source_errors.each do |error|
          if state_errors
            target_errors.add(:base, "#{I18n.t("funes.events.led_to_invalid_state_prefix")}: #{error.full_message}")
          else
            target_errors.add(error.attribute, error.message)
          end
        end
      end
  end
end
