require "test_helper"
require "minitest/spec"

class TransactionalControlForNewEventsTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  module Events
    class ValidEvent < Funes::Event
      attribute :value, :integer
    end
  end

  class WorkingProjection < Funes::Projection
    materialization_model UnitTests::Materialization

    interpretation_for Events::ValidEvent do |state, event, _as_of|
      state.assign_attributes(value: event.value)
      state
    end
  end

  class FailingProjection < Funes::Projection
    materialization_model UnitTests::Materialization

    interpretation_for Events::ValidEvent do |state, _event, _as_of|
      state.assign_attributes(value: nil) # violates a NOT NULL constraint
      state
    end
  end

  describe "when EventEntry insertion fails" do
    class StreamForEventConstraintTest < Funes::EventStream
      add_transactional_projection WorkingProjection
    end

    it "does not run transactional projections when event persistence fails due to version conflict" do
      idx = "txn-event-constraint-#{SecureRandom.uuid}"
      event_stream_instance = StreamForEventConstraintTest.for(idx)
      event = Events::ValidEvent.new(value: 42)

      Funes::EventEntry.create!(klass: Events::ValidEvent.name,
                                idx: idx,
                                props: { value: 100 },
                                version: 1)

      assert_no_difference -> { UnitTests::Materialization.count }, "No event should be created" do
        event_stream_instance.append!(event)
      end
      assert event.errors[:base].present?, "The racing condition error should be added to the event's errors"
      refute UnitTests::Materialization.exists?(idx: idx), "No materialization was created for this idx"
    end
  end

  describe "when a single transactional projection fails" do
    class StreamWithSingleFailingProjection < Funes::EventStream
      add_transactional_projection FailingProjection
    end

    it "rolls back the event when projection constraint violation occurs" do
      idx = "txn-single-proj-fail-#{SecureRandom.uuid}"
      event = Events::ValidEvent.new(value: 42)

      assert_no_difference -> { Funes::EventEntry.count }, "No event should be created" do
        StreamWithSingleFailingProjection.for(idx).append!(event)
      end

      assert event.errors[:base].present?, "The error should be added to the event's errors"
      refute Funes::EventEntry.exists?(idx: idx), "EventEntry should not exist after rollback"
      refute UnitTests::Materialization.exists?(idx: idx), "Materialization should not exist after rollback"
    end
  end

  describe "when one of multiple transactional projections fails" do
    class StreamWithMultipleProjections < Funes::EventStream
      add_transactional_projection WorkingProjection
      add_transactional_projection FailingProjection
    end

    it "rolls back event AND first projection when second projection fails (all-or-nothing)" do
      idx = "txn-multi-proj-fail-#{SecureRandom.uuid}"
      event = Events::ValidEvent.new(value: 42)

      assert_no_difference -> { Funes::EventEntry.count }, "No event should be created" do
        StreamWithMultipleProjections.for(idx).append!(event)
      end

      assert event.errors[:base].present?, "The error should be added to the event's errors"
      refute Funes::EventEntry.exists?(idx: idx), "EventEntry should not exist after rollback"
      refute UnitTests::Materialization.exists?(idx: idx),
             "Materialization should not exist (for both projections) after rollback"
    end
  end
end
