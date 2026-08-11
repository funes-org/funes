require "test_helper"
require "minitest/spec"

class Funes::MaterializationAssociationsTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  class CustomerAssigned < Funes::Event
    refers_to :customer, class_name: "Examples::Customer"
  end

  class CustomerRemoved < Funes::Event; end

  class CustomerIdAssigned < Funes::Event
    attribute :customer_id
  end

  class PartiesAssigned < Funes::Event
    refers_to :customer, class_name: "Examples::Customer"
    refers_to :account, class_name: "Examples::Account"
  end

  class VirtualM13nModel
    include ActiveModel::Model
    include ActiveModel::Attributes
    include Funes::Associations

    attribute :idx, :string
    refers_to :customer, class_name: "Examples::Customer"
  end

  class VirtualProjection < Funes::Projection
    materialization_model VirtualM13nModel

    interpretation_for CustomerAssigned do |state, event, _at|
      state.customer = event.customer
      state
    end

    interpretation_for CustomerRemoved do |state, _event, _at|
      state.customer = nil
      state
    end

    interpretation_for CustomerIdAssigned do |state, event, _at|
      state.customer_id = event.customer_id
      state
    end
  end

  class TwoModelsM13nModel
    include ActiveModel::Model
    include ActiveModel::Attributes
    include Funes::Associations

    attribute :idx, :string
    refers_to :customer, class_name: "Examples::Customer"
    refers_to :account, class_name: "Examples::Account"
  end

  class TwoModelsProjection < Funes::Projection
    materialization_model TwoModelsM13nModel

    interpretation_for PartiesAssigned do |state, event, _at|
      state.customer = event.customer
      state.account = event.account
      state
    end
  end

  let(:customer) { Examples::Customer.create!(name: "Ada") }
  let(:other_customer) { Examples::Customer.create!(name: "Grace") }
  let(:account) { Examples::Account.create!(number: "ACC-1") }

  describe "carries properly the foreign key attribute" do
    class CustomForeignKeyM13nModel
      include ActiveModel::Model
      include ActiveModel::Attributes
      include Funes::Associations

      attribute :idx, :string
      refers_to :account, class_name: "Examples::Customer", foreign_key: :account_uuid
    end

    class CustomForeignKeyProjection < Funes::Projection
      materialization_model CustomForeignKeyM13nModel

      interpretation_for CustomerAssigned do |state, event, _at|
        state.account = event.customer
        state
      end
    end

    it "stores only the foreign key in the state attributes" do
      state = VirtualProjection.process_events([ CustomerAssigned.new(customer: customer) ])

      assert_equal customer.id, state.attributes["customer_id"]
      refute_includes state.attributes.keys, "customer"
    end

    it "takes its name from the foreign_key option when one is given" do
      state = CustomForeignKeyProjection.process_events([ CustomerAssigned.new(customer: customer) ])

      assert_includes state.attributes.keys, "account_uuid"
      assert_equal customer.id, state.account_uuid
    end

    it "keeps a separate foreign key per reference" do
      state = TwoModelsProjection.process_events([ PartiesAssigned.new(customer: customer, account: account) ])

      assert_equal customer.id, state.customer_id
      assert_equal account.id, state.account_id
    end
  end

  describe "assigning a reference during interpretation" do
    it "keeps the reference assigned by the last event" do
      state = VirtualProjection.process_events([ CustomerAssigned.new(customer: customer),
                                                 CustomerAssigned.new(customer: other_customer) ])

      assert_equal other_customer.id, state.customer_id
      assert_equal other_customer, state.customer
    end

    it "clears the reference when an interpretation assigns nil" do
      state = VirtualProjection.process_events([ CustomerAssigned.new(customer: customer),
                                                 CustomerRemoved.new ])

      assert_nil state.customer_id
      assert_nil state.customer
    end
  end

  describe "the reference cache across a fold" do
    it "reloads the record when a later interpretation writes the foreign key" do
      state = VirtualProjection.process_events([ CustomerAssigned.new(customer: customer),
                                                 CustomerIdAssigned.new(customer_id: other_customer.id) ])

      assert_equal other_customer, state.customer
    end

    it "keeps the cached instance while the foreign key is unchanged" do
      state = VirtualProjection.process_events([ CustomerAssigned.new(customer: customer),
                                                 CustomerIdAssigned.new(customer_id: customer.id) ])

      assert_same customer, state.customer, "same instance proves the cache survived the fold"
    end
  end

  describe "materializing the state" do
    it "resolves the reference from the rebuilt state" do
      materialized = VirtualProjection.materialize!([ CustomerAssigned.new(customer_id: customer.id) ], "mat-1")

      assert_equal customer, materialized.customer
    end

    it "resolves each reference to its own class" do
      materialized = TwoModelsProjection.materialize!(
        [ PartiesAssigned.new(customer: customer, account: account) ], "mat-2")

      assert_equal customer, materialized.customer
      assert_equal account, materialized.account
    end

    it "reads a dangling reference as nil while keeping the foreign key" do
      event = CustomerAssigned.new(customer: customer)
      customer.destroy!

      materialized = VirtualProjection.materialize!([ event ], "mat-3")

      assert_equal customer.id, materialized.customer_id
      assert_nil materialized.customer
    end
  end

  describe "a reference declared as required" do
    class RequiredReferenceM13nModel
      include ActiveModel::Model
      include ActiveModel::Attributes
      include Funes::Associations

      attribute :idx, :string
      refers_to :customer, class_name: "Examples::Customer", required: true
    end

    class RequiredReferenceProjection < Funes::Projection
      materialization_model RequiredReferenceM13nModel

      interpretation_for CustomerAssigned do |state, event, _at|
        state.customer = event.customer
        state
      end
    end

    it "makes the state invalid when no interpretation assigns it" do
      state = RequiredReferenceProjection.process_events([])

      refute state.valid?
      assert_includes state.errors[:customer_id], "can't be blank"
    end

    it "makes the state valid once an interpretation assigns it" do
      state = RequiredReferenceProjection.process_events([ CustomerAssigned.new(customer: customer) ])

      assert state.valid?
    end
  end
end
