require "test_helper"
require "minitest/spec"

class Funes::EventAssociationsTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  class ReferencingEvent < Funes::Event
    refers_to :customer, class_name: "Examples::Customer"
  end

  class RequiredReferenceEvent < Funes::Event
    refers_to :owner, class_name: "Examples::Customer", required: true
  end

  class CustomForeignKeyEvent < Funes::Event
    refers_to :account, class_name: "Examples::Customer", foreign_key: :account_uuid
  end

  class TwoModelsEvent < Funes::Event
    refers_to :customer, class_name: "Examples::Customer"
    refers_to :account, class_name: "Examples::Account"
  end

  class SameModelTwiceEvent < Funes::Event
    refers_to :buyer, class_name: "Examples::Customer"
    refers_to :seller, class_name: "Examples::Customer"
  end

  class SharedForeignKeyEvent < Funes::Event
    refers_to :buyer, class_name: "Examples::Customer", foreign_key: :customer_id
    refers_to :seller, class_name: "Examples::Customer", foreign_key: :customer_id
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

  describe "foreign key reassignment" do
    let(:other_customer) { Examples::Customer.create!(name: "Grace") }

    it "reloads the reference assigned as a record" do
      event = ReferencingEvent.new(customer: customer)
      event.customer_id = other_customer.id

      assert_equal other_customer, event.customer
    end

    it "reloads a lazily loaded reference" do
      event = ReferencingEvent.new(customer_id: customer.id)
      event.customer # populate the cache
      event.customer_id = other_customer.id

      assert_equal other_customer, event.customer
    end

    it "keeps the cached instance when set back to the same id" do
      event = ReferencingEvent.new(customer: customer)
      event.customer_id = other_customer.id
      event.customer_id = customer.id

      assert_same customer, event.customer
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
          refers_to :customer, class_name: Examples::Customer
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

  describe "multiple references to different models" do
    let(:account) { Examples::Account.create!(number: "ACC-1") }

    it "keeps a separate foreign key per reference" do
      event = TwoModelsEvent.new(customer: customer, account: account)

      assert_equal customer.id, event.customer_id
      assert_equal account.id, event.account_id
    end

    it "resolves each reference to its own class" do
      # Rebuilding from attributes bypasses the writer's cache, so each reference has to
      # resolve its own class_name and load by id for real.
      rehydrated = TwoModelsEvent.new(TwoModelsEvent.new(customer: customer, account: account).attributes)

      assert_equal customer, rehydrated.customer
      assert_equal account, rehydrated.account
    end
  end

  describe "multiple references to the same model" do
    let(:other_customer) { Examples::Customer.create!(name: "Grace") }

    it "keeps the references independent" do
      event = SameModelTwiceEvent.new(buyer: customer, seller: other_customer)

      assert_equal customer, event.buyer
      assert_equal other_customer, event.seller
    end

    it "reloads only the reference whose foreign key changed" do
      event = SameModelTwiceEvent.new(buyer: customer, seller: other_customer)
      event.buyer_id = other_customer.id

      assert_equal other_customer, event.buyer
      assert_same other_customer, event.seller
    end

    it "allows both references to point at the same record" do
      event = SameModelTwiceEvent.new(buyer: customer, seller: customer)

      assert_equal customer.id, event.buyer_id
      assert_equal customer.id, event.seller_id
    end
  end

  describe "two references sharing one foreign key" do
    it "makes them aliases of each other" do
      # A degenerate declaration: one attribute backs both references, so writing either
      # moves both. Documented here so the behaviour is not mistaken for a bug.
      event = SharedForeignKeyEvent.new(buyer: customer)

      assert_equal [ "customer_id" ], event.attributes.keys
      assert_equal customer, event.seller
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
