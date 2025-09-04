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
    interpretation_for TestEvent do |state, event, as_of|
      state.assign_attributes(
        total: state.total + event.amount,
        count: state.count + 1,
        last_note: event.note,
        recorded_at: as_of
      )
      state
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

      result = interpret_event_based_on(TestProjection, event, initial_state)

      assert_instance_of TestState, result
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

    it "passes as_of parameter to interpretation block" do
      initial_state = TestState.new
      event = TestEvent.new(amount: 100, note: "test")
      as_of = Time.new(2023, 5, 10, 10, 30, 0)

      result = interpret_event_based_on(TestProjection, event, initial_state, as_of)

      assert_equal as_of, result.recorded_at
    end

    it "uses Time.current as default as_of when not provided" do
      initial_state = TestState.new
      event = TestEvent.new(amount: 100, note: "test")

      freeze_time do
        result = interpret_event_based_on(TestProjection, event, initial_state)

        assert_equal Time.current, result.recorded_at
      end
    end

    it "does not mutate the original state" do
      initial_state = TestState.new(total: 100, count: 5)
      interpret_event_based_on(TestProjection, TestEvent.new(amount: 50, note: "test"), initial_state)

      assert_equal 150, initial_state.total
    end
  end
end
