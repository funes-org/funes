# frozen_string_literal: true

module Funes
  # Declares references from an event to other models, accessible at interpretation time.
  #
  # Events are immutable facts serialized as plain JSON in the +props+ column, so an event cannot
  # store another model directly. The +references+ macro stores only the referenced record's id as a
  # regular event attribute (and therefore in +props+), while exposing a reader that lazily loads the
  # record by id and a writer that accepts the record itself.
  #
  # The reader returns the record's *current* state (a live lookup via +find_by+), not a snapshot of
  # how it looked when the event was recorded. A reference whose record no longer exists reads as
  # +nil+ rather than raising.
  #
  # == Example
  #
  #   class Deposit::Opened < Funes::Event
  #     references :customer
  #   end
  #
  #   event = Deposit::Opened.new(customer: some_customer)
  #   event.customer_id      # => some_customer.id  (this is what gets serialized)
  #   event.customer         # => some_customer
  #
  #   # Inside an interpretation block, the reference is read straight off the event:
  #   interpretation_for Deposit::Opened do |state, event, _at|
  #     state.customer = event.customer
  #     state
  #   end
  #
  # == Options
  #
  # * +class_name+ - The name of the referenced class. Defaults to the camelized reference name
  #   (e.g. +references :customer+ infers +"Customer"+). Resolved lazily, so it plays well with
  #   autoloading and namespaced constants.
  # * +foreign_key+ - The attribute that stores the id. Defaults to +"#{name}_id"+.
  # * +required+ - When +true+, adds a presence validation on the foreign key so an event without the
  #   reference is invalid and will not be persisted. Defaults to +false+ (ActiveRecord-style).
  #
  #   class Loan::Granted < Funes::Event
  #     references :borrower, class_name: "User", required: true
  #     references :account, foreign_key: :account_uuid
  #   end
  module Associations
    extend ActiveSupport::Concern

    module ClassMethods
      # Declares a reference to another model. See {Funes::Associations} for details.
      #
      # @param name [Symbol] The reference name (defines +name+ / +name=+ accessors).
      # @param class_name [String, nil] Name of the referenced class. Defaults to +name.camelize+.
      # @param foreign_key [Symbol, String, nil] Attribute storing the id. Defaults to +"#{name}_id"+.
      # @param required [Boolean] Whether to validate presence of the foreign key. Defaults to +false+.
      # @return [void]
      def references(name, class_name: nil, foreign_key: nil, required: false)
        fk        = (foreign_key || "#{name}_id").to_sym
        klass_str = (class_name || name.to_s.camelize).to_s

        # Untyped (pass-through Value) attribute so integer and string/UUID ids both round-trip
        # through JSON unchanged. This is what gets serialized into +props+.
        attribute fk

        define_method(name) do
          id = public_send(fk)
          return nil if id.nil?

          (@__reference_cache ||= {}).fetch(name) do
            @__reference_cache[name] = klass_str.constantize.find_by(id: id)
          end
        end

        define_method("#{name}=") do |record|
          @__reference_cache ||= {}
          if record.nil?
            public_send("#{fk}=", nil)
            @__reference_cache.delete(name)
          else
            public_send("#{fk}=", record.id)
            @__reference_cache[name] = record
          end
        end

        validates fk, presence: true if required
      end
    end
  end
end
