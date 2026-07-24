require "test_helper"
require "minitest/spec"

class Funes::EventAssociationsTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  class ReferencingEvent < Funes::Event
    references :customer, class_name: "Examples::Customer"
  end

  class RequiredReferenceEvent < Funes::Event
    references :owner, class_name: "Examples::Customer", required: true
  end

  class CustomForeignKeyEvent < Funes::Event
    references :account, class_name: "Examples::Customer", foreign_key: :account_uuid
  end

  let(:customer) { Examples::Customer.create!(name: "Ada") }

  describe "foreign key attribute" do
    it "exposes the foreign key as a serializable attribute" do
      event = ReferencingEvent.new(customer: customer)

      assert_includes event.attributes.keys, "customer_id"
      assert_equal customer.id, event.attributes["customer_id"]
    end

    it "does not leak the reference accessor into attributes" do
      event = ReferencingEvent.new(customer: customer)

      refute_includes event.attributes.keys, "customer"
    end
  end

  describe "writer" do
    it "stores the record id and reads the assigned instance back without reloading" do
      event = ReferencingEvent.new
      event.customer = customer

      assert_equal customer.id, event.customer_id
      # A reload would return a different object; same instance proves the writer's cache is used.
      assert_same customer, event.customer
    end

    it "clears the foreign key when assigned nil" do
      event = ReferencingEvent.new(customer: customer)
      event.customer = nil

      assert_nil event.customer_id
      assert_nil event.customer
    end
  end

  describe "reader" do
    it "lazily loads the record from a foreign key id" do
      event = ReferencingEvent.new(customer_id: customer.id)

      assert_equal customer, event.customer
    end

    it "returns nil when no reference is set" do
      assert_nil ReferencingEvent.new.customer
    end

    it "returns nil for a dangling reference" do
      event = ReferencingEvent.new(customer_id: customer.id)
      customer.destroy!

      assert_nil event.customer
    end
  end

  describe "serialization round-trip" do
    it "survives persistence and rehydration via the event entry" do
      event = ReferencingEvent.new(customer: customer)
      Funes::EventEntry.create!(klass: ReferencingEvent.name, idx: "assoc-1", version: 1,
                                props: event.attributes, created_at: Time.current, occurred_at: Time.current)

      rehydrated = Funes::EventEntry.find_by(idx: "assoc-1").to_klass_instance

      assert_equal customer.id, rehydrated.customer_id
      assert_equal customer, rehydrated.customer
    end
  end

  describe "required: true" do
    it "is invalid without the reference" do
      event = RequiredReferenceEvent.new

      refute event.valid?
      assert_includes event.errors[:owner_id], "can't be blank"
    end

    it "is valid with the reference" do
      assert RequiredReferenceEvent.new(owner: customer).valid?
    end
  end

  describe "optional by default" do
    it "is valid without the reference" do
      assert ReferencingEvent.new.valid?
    end
  end

  describe "class_name: given as a class" do
    it "raises ArgumentError, matching ActiveRecord's behavior" do
      error = assert_raises(ArgumentError) do
        Class.new(Funes::Event) do
          references :customer, class_name: Examples::Customer
        end
      end

      assert_equal "A class was passed to `:class_name` but we are expecting a string.", error.message
    end
  end

  describe "foreign_key: option" do
    it "uses the configured attribute name" do
      event = CustomForeignKeyEvent.new(account: customer)

      assert_equal customer.id, event.account_uuid
      assert_includes event.attributes.keys, "account_uuid"
      assert_equal customer, event.account
    end
  end

  describe "use at interpretation time" do
    Projection = Class.new(Funes::Projection) do
      materialization_model Struct.new(:customer, keyword_init: true)

      initial_state { |model, _at| model.new }

      interpretation_for ReferencingEvent do |state, event, _at|
        state.customer = event.customer
        state
      end
    end

    it "reads the referenced record off the event" do
      event = ReferencingEvent.new(customer_id: customer.id)
      state = Projection.process_events([ event ])

      assert_equal customer, state.customer
    end
  end
end
