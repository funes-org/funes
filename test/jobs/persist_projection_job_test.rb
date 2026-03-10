require "test_helper"
require "minitest/spec"
require "minitest/mock"

class PersistProjectionJobTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  class TestEvent < Funes::Event
    attribute :amount, :integer
    attribute :at, :date
  end

  class TestMaterialization < ApplicationRecord
    self.table_name = "materializations"
  end

  class TestProjection < Funes::Projection
    materialization_model TestMaterialization

    initial_state do
      TestMaterialization.new
    end

    interpretation_for TestEvent do |state, event, _as_of|
      current = state.value || 0
      state.assign_attributes(value: current + event.amount)
      state
    end
  end

  describe "#perform" do
    it "materializes and persists a projection from event stream events" do
      idx = "test-123"

      Funes::EventEntry.create!(klass: "PersistProjectionJobTest::TestEvent",
                                idx: idx,
                                version: 1,
                                props: { amount: 100, at: Date.today },
                                occurred_at: Time.current)

      assert_nil TestMaterialization.find_by(idx: idx)

      Funes::PersistProjectionJob.perform_now(idx, TestProjection)

      materialization = TestMaterialization.find_by(idx: idx)
      assert_not_nil materialization
      assert_equal 100, materialization.value
    end

    it "processes multiple events and updates the projection state" do
      idx = "test-456"

      Funes::EventEntry.create!(klass: "PersistProjectionJobTest::TestEvent",
                                idx: idx,
                                version: 1,
                                props: { amount: 100, at: Date.today },
                                occurred_at: Time.current)

      Funes::EventEntry.create!(klass: "PersistProjectionJobTest::TestEvent",
                                idx: idx,
                                version: 2,
                                props: { amount: 50, at: Date.today },
                                occurred_at: Time.current)

      Funes::PersistProjectionJob.perform_now(idx, TestProjection, Time.current)

      materialization = TestMaterialization.find_by(idx: idx)
      assert_equal 150, materialization.value
    end

    it "respects as_of parameter to filter events by time" do
      idx = "test-temporal"

      Funes::EventEntry.create!(klass: "PersistProjectionJobTest::TestEvent",
                                idx: idx,
                                version: 1,
                                props: { amount: 100, at: Date.new(2025, 1, 1) },
                                created_at: Time.new(2025, 1, 1, 12, 0, 0),
                                occurred_at: Time.new(2025, 1, 1, 12, 0, 0))

      Funes::EventEntry.create!(klass: "PersistProjectionJobTest::TestEvent",
                                idx: idx,
                                version: 2,
                                props: { amount: 50, at: Date.new(2025, 2, 1) },
                                created_at: Time.new(2025, 2, 1, 12, 0, 0),
                                occurred_at: Time.new(2025, 2, 1, 12, 0, 0))

      as_of = Time.new(2025, 1, 15, 12, 0, 0)
      Funes::PersistProjectionJob.perform_now(idx, TestProjection, as_of)

      materialization = TestMaterialization.find_by(idx: idx)
      assert_equal 100, materialization.value
    end

    it "updates existing projection when called multiple times" do
      idx = "test-update"

      Funes::EventEntry.create!(klass: "PersistProjectionJobTest::TestEvent",
                                idx: idx,
                                version: 1,
                                props: { amount: 100, at: Date.today },
                                occurred_at: Time.current)

      Funes::PersistProjectionJob.perform_now(idx, TestProjection, Time.current)
      assert_equal 100, TestMaterialization.find_by(idx: idx).value

      Funes::EventEntry.create!(klass: "PersistProjectionJobTest::TestEvent",
                                idx: idx,
                                version: 2,
                                props: { amount: 50, at: Date.today },
                                occurred_at: Time.current)

      Funes::PersistProjectionJob.perform_now(idx, TestProjection, Time.current)

      materialization = TestMaterialization.find_by(idx: idx)
      assert_equal 150, materialization.value
    end

    it "passes the at parameter to materialize! as temporal context" do
      idx = "test-at-context"
      at_time = Time.new(2025, 6, 15, 12, 0, 0)

      Funes::EventEntry.create!(klass: "PersistProjectionJobTest::TestEvent",
                                idx: idx,
                                version: 1,
                                props: { amount: 100, at: Date.new(2025, 6, 15) },
                                occurred_at: at_time)

      mock = Minitest::Mock.new
      mock.expect(:call, true, [ Array, idx ], at: at_time)

      TestProjection.stub(:materialize!, mock) do
        Funes::PersistProjectionJob.perform_now(idx, TestProjection, nil, at_time)
      end

      assert_mock mock
    end
  end
end
