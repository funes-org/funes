require "test_helper"
require "minitest/spec"

class PersistProjectionJobTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  class TestEvent < Funes::Event
    attribute :amount, :float
    attribute :note, :string
    attribute :at, :date
  end

  class TestMaterialization < ApplicationRecord
    self.table_name = "debt_collections"
    enum :status, unpaid: 0, paid: 1
  end

  class TestProjection < Funes::Projection
    materialization_model TestMaterialization

    initial_state do
      TestMaterialization.new
    end

    interpretation_for TestEvent do |state, event, _as_of|
      current_total = state.outstanding_balance || 0
      new_balance = current_total + event.amount

      state.assign_attributes(
        outstanding_balance: new_balance,
        issuance_date: state.issuance_date || event.at || Date.today,
        status: new_balance.zero? ? :paid : :unpaid
      )
      state
    end
  end

  describe "#perform" do
    it "materializes and persists a projection from event stream events" do
      idx = "test-123"

      Funes::EventEntry.create!(
        klass: "PersistProjectionJobTest::TestEvent",
        idx: idx,
        version: 1,
        props: { amount: 100.0, note: "first", at: Date.today },
        occurred_at: Time.current
      )

      assert_nil TestMaterialization.find_by(idx: idx)

      Funes::PersistProjectionJob.perform_now(idx, TestProjection)

      materialization = TestMaterialization.find_by(idx: idx)
      assert_not_nil materialization
      assert_equal 100.0, materialization.outstanding_balance
      assert_equal "unpaid", materialization.status
    end

    it "processes multiple events and updates the projection state" do
      idx = "test-456"

      Funes::EventEntry.create!(
        klass: "PersistProjectionJobTest::TestEvent",
        idx: idx,
        version: 1,
        props: { amount: 100.0, note: "first", at: Date.today },
        occurred_at: Time.current
      )
      Funes::EventEntry.create!(
        klass: "PersistProjectionJobTest::TestEvent",
        idx: idx,
        version: 2,
        props: { amount: 50.0, note: "second", at: Date.today },
        occurred_at: Time.current
      )

      Funes::PersistProjectionJob.perform_now(idx, TestProjection, Time.current)

      materialization = TestMaterialization.find_by(idx: idx)
      assert_equal 150.0, materialization.outstanding_balance
    end

    it "respects as_of parameter to filter events by time" do
      idx = "test-temporal"

      Funes::EventEntry.create!(
        klass: "PersistProjectionJobTest::TestEvent",
        idx: idx,
        version: 1,
        props: { amount: 100.0, note: "first", at: Date.new(2025, 1, 1) },
        created_at: Time.new(2025, 1, 1, 12, 0, 0),
        occurred_at: Time.new(2025, 1, 1, 12, 0, 0)
      )
      Funes::EventEntry.create!(
        klass: "PersistProjectionJobTest::TestEvent",
        idx: idx,
        version: 2,
        props: { amount: 50.0, note: "second", at: Date.new(2025, 2, 1) },
        created_at: Time.new(2025, 2, 1, 12, 0, 0),
        occurred_at: Time.new(2025, 2, 1, 12, 0, 0)
      )

      as_of = Time.new(2025, 1, 15, 12, 0, 0)
      Funes::PersistProjectionJob.perform_now(idx, TestProjection, as_of)

      materialization = TestMaterialization.find_by(idx: idx)
      assert_equal 100.0, materialization.outstanding_balance
    end

    it "updates existing projection when called multiple times" do
      idx = "test-update"

      Funes::EventEntry.create!(
        klass: "PersistProjectionJobTest::TestEvent",
        idx: idx,
        version: 1,
        props: { amount: 100.0, note: "first", at: Date.today },
        occurred_at: Time.current
      )

      Funes::PersistProjectionJob.perform_now(idx, TestProjection, Time.current)
      assert_equal 100.0, TestMaterialization.find_by(idx: idx).outstanding_balance

      Funes::EventEntry.create!(
        klass: "PersistProjectionJobTest::TestEvent",
        idx: idx,
        version: 2,
        props: { amount: 50.0, note: "second", at: Date.today },
        occurred_at: Time.current
      )

      Funes::PersistProjectionJob.perform_now(idx, TestProjection, Time.current)

      materialization = TestMaterialization.find_by(idx: idx)
      assert_equal 150.0, materialization.outstanding_balance
    end
  end
end
