require "test_helper"
require "minitest/spec"

class Funes::EventAssociationsTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  class ReferencingEvent < Funes::Event
    refers_to :customer, class_name: "Examples::Customer"
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

  let(:customer) { Examples::Customer.create!(name: "Ada") }
  let(:other_customer) { Examples::Customer.create!(name: "Grace") }
  let(:account) { Examples::Account.create!(number: "ACC-1") }

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

    it "takes its name from the foreign_key option when one is given" do
      event = CustomForeignKeyEvent.new(account: customer)

      assert_includes event.attributes.keys, "account_uuid"
      assert_equal customer.id, event.account_uuid
    end

    it "keeps a separate foreign key per reference" do
      event = TwoModelsEvent.new(customer: customer, account: account)

      assert_equal customer.id, event.customer_id
      assert_equal account.id, event.account_id
    end
  end

  describe "assigning a record to the reference" do
    it "stores the record id and reads the assigned instance back without reloading" do
      event = ReferencingEvent.new
      event.customer = customer

      assert_equal customer.id, event.customer_id
      assert_same customer, event.customer, "same instance proves the writer's cache is used"
    end

    it "replaces a record previously assigned to the same reference" do
      event = ReferencingEvent.new(customer: customer)
      event.customer = other_customer

      assert_equal other_customer.id, event.customer_id
      assert_same other_customer, event.customer, "same instance proves the writer's cache is used"
    end

    it "clears the foreign key when assigned nil" do
      event = ReferencingEvent.new(customer: customer)
      event.customer = nil

      assert_nil event.customer_id
      assert_nil event.customer
    end
  end

  describe "loading the record from the foreign key" do
    it "lazily loads it when the event is created with foreign key" do
      event = ReferencingEvent.new(customer_id: customer.id)

      assert_equal customer, event.customer
      assert_not_same customer, event.customer, "different instances prove there is no cache being used"
    end

    it "loads it through a custom foreign key" do
      event = CustomForeignKeyEvent.new(account_uuid: customer.id)

      assert_equal customer, event.account
    end

    it "resolves each reference to its own class" do
      event = TwoModelsEvent.new(customer_id: customer.id, account_id: account.id)

      assert_equal customer, event.customer
      assert_equal account, event.account
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

  describe "the reference cache" do
    it "reloads the record when the foreign key changes" do
      event = ReferencingEvent.new(customer: customer)
      event.customer_id = other_customer.id

      assert_equal other_customer, event.customer
    end

    it "keeps the cached instance when the foreign key returns to the same id" do
      event = ReferencingEvent.new(customer: customer)
      event.customer_id = other_customer.id
      event.customer_id = customer.id

      assert_same customer, event.customer, "same instance proves the cache survived the round trip"
    end
  end

  describe "persisting and rehydrating the event" do
    it "restores the reference from the stored foreign key" do
      Funes::EventEntry.create!(klass: ReferencingEvent.name, idx: "assoc-1", version: 1,
                                props: ReferencingEvent.new(customer: customer).attributes,
                                created_at: Time.current, occurred_at: Time.current)
      rehydrated = Funes::EventEntry.find_by(idx: "assoc-1", version: 1).to_klass_instance

      assert_equal customer.id, rehydrated.customer_id
      assert_equal customer, rehydrated.customer
    end
  end

  describe "a reference declared as required" do
    class RequiredReferenceEvent < Funes::Event
      refers_to :owner, class_name: "Examples::Customer", required: true
    end

    it "makes the event invalid when the reference is missing" do
      event = RequiredReferenceEvent.new

      refute event.valid?
      assert_includes event.errors[:owner_id], "can't be blank"
    end

    it "makes the event valid when the reference is set" do
      assert RequiredReferenceEvent.new(owner: customer).valid?
    end
  end

  describe "a reference is optional by default" do
    it "leaves the event valid when the reference is missing" do
      assert ReferencingEvent.new.valid?,
             "`customer` reference is not set as required in the ReferencingEvent definition"
    end
  end

  describe "a reference whose class_name is given as a constant" do
    it "raises ArgumentError, as belongs_to and the other ActiveRecord association macros do" do
      error = assert_raises(ArgumentError) do
        Class.new(Funes::Event) do
          refers_to :customer, class_name: Examples::Customer
        end
      end

      assert_equal "A class was passed to `:class_name` but we are expecting a string.", error.message
    end
  end

  describe "multiple references to the same model" do
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
end
