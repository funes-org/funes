require "test_helper"
require "minitest/spec"

class Funes::ProjectionTestHelperTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL
  include Funes::ProjectionTestHelper

  class TestEvent < Funes::Event
    attribute :amount, :integer
    attribute :note, :string
  end

  class TestState
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :total, :integer, default: 0
    attribute :count, :integer, default: 0
    attribute :last_note, :string
    attribute :recorded_at, :datetime
  end

  class TestProjection < Funes::Projection
    interpretation_for TestEvent do |state, event, at|
      state.assign_attributes(
        total: state.total + event.amount,
        count: state.count + 1,
        last_note: event.note,
        recorded_at: at
      )
      state
    end
  end

  class InitialStateProjection < Funes::Projection
    materialization_model TestState

    initial_state do |materialization_model, at|
      materialization_model.new(total: 42, recorded_at: at)
    end
  end

  class FinalStateProjection < Funes::Projection
    final_state do |state, at|
      state.assign_attributes(last_note: "finalized", recorded_at: at)
      state
    end
  end

  describe "#build_initial_state_based_on" do
    it "returns the custom initial state" do
      result = build_initial_state_based_on(InitialStateProjection)

      assert_instance_of TestState, result
      assert_equal 42, result.total
    end

    it "passes at parameter to initial_state block" do
      at = Time.new(2023, 5, 10, 10, 30, 0)

      assert_equal at, build_initial_state_based_on(InitialStateProjection, at).recorded_at
    end

    it "uses Time.current as default at when not provided" do
      freeze_time do
        assert_equal Time.current, build_initial_state_based_on(InitialStateProjection).recorded_at
      end
    end
  end

  describe "#interpret_event_based_on" do
    it "interprets an event and transforms the state" do
      result = interpret_event_based_on(TestProjection,
                                        TestEvent.new(amount: 50, note: "test"),
                                        TestState.new(total: 100, count: 5))
      assert_equal 150, result.total
      assert_equal 6, result.count
      assert_equal "test", result.last_note
    end

    it "returns the same state object type" do
      initial_state = TestState.new
      event = TestEvent.new(amount: 10, note: "hello")

      assert_instance_of TestState, interpret_event_based_on(TestProjection, event, initial_state)
    end

    it "handles multiple sequential interpretations" do
      state = interpret_event_based_on(TestProjection, TestEvent.new(amount: 100, note: "first"), TestState.new)
      assert_equal 100, state.total
      assert_equal "first", state.last_note
      assert_equal 1, state.count

      state = interpret_event_based_on(TestProjection, TestEvent.new(amount: 50, note: "second"), state)
      assert_equal 150, state.total
      assert_equal 2, state.count
      assert_equal "second", state.last_note
    end

    it "passes at parameter to interpretation block" do
      initial_state = TestState.new
      event = TestEvent.new(amount: 100, note: "test")
      at = Time.new(2023, 5, 10, 10, 30, 0)

      assert_equal at, interpret_event_based_on(TestProjection, event, initial_state, at).recorded_at
    end

    it "uses Time.current as default at when not provided" do
      initial_state = TestState.new
      event = TestEvent.new(amount: 100, note: "test")

      freeze_time do
        assert_equal Time.current, interpret_event_based_on(TestProjection, event, initial_state).recorded_at
      end
    end
  end

  describe "#apply_final_state_based_on" do
    it "transforms state correctly" do
      state = TestState.new(total: 100, count: 3)
      result = apply_final_state_based_on(FinalStateProjection, state)

      assert_equal "finalized", result.last_note
      assert_equal 100, result.total
    end

    it "passes at parameter to final_state block" do
      at = Time.new(2023, 5, 10, 10, 30, 0)
      state = TestState.new

      assert_equal at, apply_final_state_based_on(FinalStateProjection, state, at).recorded_at
    end

    it "uses Time.current as default at when not provided" do
      freeze_time do
        state = TestState.new

        assert_equal Time.current, apply_final_state_based_on(FinalStateProjection, state).recorded_at
      end
    end
  end
end
