# frozen_string_literal: true

module Funes
  # Declares references to other models, accessible at interpretation time.
  #
  # Events are immutable facts serialized as plain JSON in the +props+ column, so an event cannot
  # store another model directly. The +refers_to+ macro stores only the referenced record's id as a
  # regular event attribute (and therefore in +props+), while exposing a reader that lazily loads the
  # record by id and a writer that accepts the record itself.
  #
  # The reader returns the record's *current* state (a live lookup via +find_by+), not a snapshot of
  # how it looked when the event was recorded. A reference whose record no longer exists reads as
  # +nil+ rather than raising. The loaded record is memoized per reference and reloaded whenever the
  # foreign key attribute changes, matching Active Record's staleness handling.
  #
  # == Example
  #
  #   class Deposit::Created < Funes::Event
  #     refers_to :customer
  #   end
  #
  #   event = Deposit::Created.new(customer: some_customer)
  #   event.customer_id      # => some_customer.id  (this is what gets serialized)
  #   event.customer         # => some_customer
  #
  #   # Inside an interpretation block, the reference is read straight off the event:
  #   interpretation_for Deposit::Created do |state, event, _at|
  #     state.customer = event.customer
  #     state
  #   end
  #
  # == Options
  #
  # * +class_name+ - The name of the referenced class, as a string (or symbol) — passing the class
  #   itself raises +ArgumentError+, as in Active Record. Defaults to the camelized reference name
  #   (e.g. +refers_to :customer+ infers +"Customer"+). Resolved lazily, so it plays well with
  #   autoloading and namespaced constants.
  # * +foreign_key+ - The attribute that stores the id. Defaults to +"#{name}_id"+.
  # * +required+ - When +true+, adds a presence validation on the foreign key so an event without the
  #   reference is invalid and will not be persisted. Defaults to +false+ (ActiveRecord-style).
  #
  #   class Loan::Granted < Funes::Event
  #     refers_to :borrower, class_name: "User", required: true
  #     refers_to :account, foreign_key: :account_uuid
  #   end
  #
  # == Requirements
  #
  # The including class must provide +ActiveModel::Attributes+, which backs the foreign key
  # attribute. Passing <tt>required: true</tt> additionally needs +ActiveModel::Validations+.
  # {Funes::Event} provides both.
  #
  # == Use on materialization models
  #
  # A projection's state is an instance of its materialization model, so a materialization model
  # that declares +refers_to+ offers interpretation blocks the same API events do — the reference
  # reads and writes identically on both sides of the block:
  #
  #   class CustomerSnapshot
  #     include ActiveModel::Model
  #     include ActiveModel::Attributes
  #     include Funes::Associations
  #
  #     refers_to :customer, class_name: "Examples::Customer"
  #   end
  #
  #   interpretation_for Deposit::Created do |state, event, _at|
  #     state.customer = event.customer
  #     state
  #   end
  #
  # Only the id travels in +attributes+, so the reference survives the rebuild that +materialize!+
  # performs. This works for both virtual materialization models and those persisted through
  # +persist_materialization_model_with+.
  #
  # For an ActiveRecord-backed materialization model, declare a regular +belongs_to+ association
  # instead: it is the idiomatic tool there, and it brings preloading and +inverse_of+ with it.
  #
  # == Namespaced models
  #
  # +class_name+ must be fully qualified, e.g. <tt>class_name: "Examples::Customer"</tt>. It is
  # resolved lazily, on the first load by id — assigning a record caches it directly, so a wrong
  # +class_name+ surfaces only when a freshly built object reads the reference, not when it is
  # assigned.
  module Associations
    extend ActiveSupport::Concern

    module ClassMethods
      # Declares a reference to another model. See {Funes::Associations} for details.
      #
      # @param name [Symbol] The reference name (defines +name+ / +name=+ accessors).
      # @param class_name [String, Symbol, nil] Name of the referenced class (not the class itself).
      #   Defaults to +name.camelize+.
      # @param foreign_key [Symbol, String, nil] Attribute storing the id. Defaults to +"#{name}_id"+.
      # @param required [Boolean] Whether to validate presence of the foreign key. Defaults to +false+.
      # @return [void]
      def refers_to(name, class_name: nil, foreign_key: nil, required: false)
        if class_name.instance_of?(Class)
          raise ArgumentError, "A class was passed to `:class_name` but we are expecting a string."
        end

        fk        = (foreign_key || "#{name}_id").to_sym
        klass_str = (class_name || name.to_s.camelize).to_s

        # Untyped (pass-through Value) attribute so integer and string/UUID ids both round-trip
        # through JSON unchanged. This is what gets serialized into +props+.
        attribute fk

        define_method(name) do
          id = public_send(fk)
          return nil if id.nil?

          # Cache entries are [id, record] pairs so a direct write to the foreign key attribute
          # invalidates the memoized record, as in ActiveRecord's stale-target handling.
          @__reference_cache ||= {}
          cached_id, cached_record = @__reference_cache[name]
          return cached_record if cached_id == id

          record = klass_str.constantize.find_by(id: id)
          @__reference_cache[name] = [ id, record ]
          record
        end

        define_method("#{name}=") do |record|
          @__reference_cache ||= {}
          if record.nil?
            public_send("#{fk}=", nil)
            @__reference_cache.delete(name)
          else
            public_send("#{fk}=", record.id)
            @__reference_cache[name] = [ record.id, record ]
          end
        end

        validates fk, presence: true if required
      end
    end
  end
end
