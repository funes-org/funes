require "test_helper"
require "minitest/spec"

# A projection's state *is* an instance of its materialization model, so `refers_to` declared on
# the materialization model gives interpretation blocks the same reader/writer API events use.
# These tests cover both flavors of ActiveModel materialization model: virtual (rebuilt in memory
# on every read) and custom destination (persisted through `persist_materialization_model_with`).
class Funes::MaterializationAssociationsTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  class CustomerAssigned < Funes::Event
    refers_to :customer, class_name: "Examples::Customer"
  end

  class VirtualState
    include ActiveModel::Model
    include ActiveModel::Attributes
    include Funes::Associations

    attribute :idx, :string
    refers_to :customer, class_name: "Examples::Customer"
  end

  class VirtualProjection < Funes::Projection
    materialization_model VirtualState

    interpretation_for CustomerAssigned do |state, event, _at|
      state.customer = event.customer
      state
    end
  end

  class StoredState
    include ActiveModel::Model
    include ActiveModel::Attributes
    include Funes::Associations

    attribute :idx, :string
    refers_to :customer, class_name: "Examples::Customer", required: true

    class << self
      attr_accessor :last_payload
    end

    def save_to_store!
      self.class.last_payload = attributes
      true
    end
  end

  class StoredProjection < Funes::Projection
    materialization_model StoredState
    persist_materialization_model_with :save_to_store!

    interpretation_for CustomerAssigned do |state, event, _at|
      state.customer = event.customer
      state
    end
  end

  let(:customer) { Examples::Customer.create!(name: "Ada") }

  before { StoredState.last_payload = nil }

  describe "virtual materialization model" do
    it "carries the reference through materialization" do
      # `materialize!` rebuilds the model from `state.attributes`, so the returned instance never
      # saw the writer's cache and has to resolve the reference by id for real.
      materialized = VirtualProjection.materialize!([ CustomerAssigned.new(customer_id: customer.id) ], "mat-1")

      assert_equal customer, materialized.customer
    end

    it "stores only the foreign key in the state attributes" do
      state = VirtualProjection.process_events([ CustomerAssigned.new(customer: customer) ])

      assert_equal customer.id, state.attributes["customer_id"]
      refute_includes state.attributes.keys, "customer"
    end

    it "reads a dangling reference as nil while keeping the foreign key" do
      event = CustomerAssigned.new(customer: customer)
      customer.destroy!

      materialized = VirtualProjection.materialize!([ event ], "mat-2")

      assert_equal customer.id, materialized.customer_id
      assert_nil materialized.customer
    end
  end

  describe "custom destination materialization model" do
    it "hands the foreign key to the persistence method" do
      StoredProjection.materialize!([ CustomerAssigned.new(customer: customer) ], "mat-3")

      assert_equal customer.id, StoredState.last_payload["customer_id"]
      assert_equal "mat-3", StoredState.last_payload["idx"]
    end

    it "rejects a missing required reference before persisting" do
      error = assert_raises(Funes::InvalidMaterializationState) do
        StoredProjection.materialize!([], "mat-4")
      end

      assert_includes error.record.errors[:customer_id], "can't be blank"
      assert_nil StoredState.last_payload
    end
  end
end
