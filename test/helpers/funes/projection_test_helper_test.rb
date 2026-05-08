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
    materialization_model TestState

    interpretation_for TestEvent do |state, event, at|
      state.assign_attributes(total: state.total + event.amount,
                              count: state.count + 1,
                              last_note: event.note,
                              recorded_at: at)
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

  class OtherProjection < Funes::Projection
    interpretation_for TestEvent do |state, event, _at|
      state.assign_attributes(total: state.total - event.amount, last_note: "other")
      state
    end
  end

  projection TestProjection

  describe ".projection" do
    class BoundTest < ActiveSupport::TestCase
      include Funes::ProjectionTestHelper
      projection TestProjection
    end

    it "binds the projection class for instances" do
      assert_equal TestProjection, BoundTest.projection_under_test
    end

    it "is inherited by subclasses" do
      subclass = Class.new(BoundTest)
      assert_equal TestProjection, subclass.projection_under_test
    end

    it "can be overridden in subclasses" do
      subclass = Class.new(BoundTest)
      subclass.projection OtherProjection
      assert_equal OtherProjection, subclass.projection_under_test
      assert_equal TestProjection, BoundTest.projection_under_test
    end
  end

  describe "#interpret" do
    it "interprets an event and transforms the state using the bound projection" do
      result = interpret(TestEvent.new(amount: 50, note: "test"),
                         given: TestState.new(total: 100, count: 5))

      assert_equal 150, result.total
      assert_equal 6, result.count
      assert_equal "test", result.last_note
    end

    it "returns the same state object type" do
      assert_instance_of TestState,
                         interpret(TestEvent.new(amount: 10, note: "hi"), given: TestState.new)
    end

    it "supports sequential interpretations via inject" do
      events = [ TestEvent.new(amount: 100, note: "first"),
                 TestEvent.new(amount: 50, note: "second") ]

      result = events.inject(TestState.new) { |state, event| interpret(event, given: state) }

      assert_equal 150, result.total
      assert_equal 2, result.count
      assert_equal "second", result.last_note
    end

    it "passes at to the interpretation block" do
      at = Time.new(2023, 5, 10, 10, 30, 0)

      assert_equal at, interpret(TestEvent.new(amount: 1, note: "x"), given: TestState.new, at: at).recorded_at
    end

    it "uses Time.current as default at" do
      freeze_time do
        assert_equal Time.current,
                     interpret(TestEvent.new(amount: 1, note: "x"), given: TestState.new).recorded_at
      end
    end

    it "coerces Date at to beginning_of_day" do
      date = Date.new(2024, 6, 1)

      result = interpret(TestEvent.new(amount: 1, note: "x"), given: TestState.new, at: date)

      assert_equal date.beginning_of_day, result.recorded_at
    end

    it "uses event.occurred_at when present, ignoring at" do
      occurred_at = Time.new(2024, 11, 5, 14, 0, 0)
      event = TestEvent.new(amount: 1, note: "x")
      event._event_entry = Funes::EventEntry.new(occurred_at: occurred_at)

      result = interpret(event, given: TestState.new, at: Time.new(2025, 3, 20))

      assert_equal occurred_at, result.recorded_at
    end

    it "uses the projection: keyword when provided, ignoring the bound one" do
      result = interpret(TestEvent.new(amount: 30, note: "x"),
                         given: TestState.new(total: 100),
                         projection: OtherProjection)

      assert_equal 70, result.total
      assert_equal "other", result.last_note
    end

    it "raises ArgumentError when no projection is bound and none is passed" do
      klass = Class.new(ActiveSupport::TestCase) do
        include Funes::ProjectionTestHelper
      end
      instance = klass.new("noop")

      assert_raises(ArgumentError) do
        instance.interpret(TestEvent.new(amount: 1, note: "x"), given: TestState.new)
      end
    end
  end

  describe "#initial_state" do
    it "returns the custom initial state of the bound projection" do
      result = initial_state(projection: InitialStateProjection)

      assert_instance_of TestState, result
      assert_equal 42, result.total
    end

    it "passes at to the initial_state block" do
      at = Time.new(2023, 5, 10, 10, 30, 0)

      assert_equal at, initial_state(at: at, projection: InitialStateProjection).recorded_at
    end

    it "uses Time.current as default at" do
      freeze_time do
        assert_equal Time.current, initial_state(projection: InitialStateProjection).recorded_at
      end
    end

    it "coerces Date at to beginning_of_day" do
      date = Date.new(2024, 6, 1)

      assert_equal date.beginning_of_day, initial_state(at: date, projection: InitialStateProjection).recorded_at
    end
  end

  describe "#final_state" do
    it "transforms state correctly" do
      result = final_state(given: TestState.new(total: 100, count: 3), projection: FinalStateProjection)

      assert_equal "finalized", result.last_note
      assert_equal 100, result.total
    end

    it "passes at to the final_state block" do
      at = Time.new(2023, 5, 10, 10, 30, 0)

      assert_equal at, final_state(given: TestState.new, at: at, projection: FinalStateProjection).recorded_at
    end

    it "uses Time.current as default at" do
      freeze_time do
        assert_equal Time.current, final_state(given: TestState.new, projection: FinalStateProjection).recorded_at
      end
    end

    it "coerces Date at to beginning_of_day" do
      date = Date.new(2024, 6, 1)

      assert_equal date.beginning_of_day,
                   final_state(given: TestState.new, at: date, projection: FinalStateProjection).recorded_at
    end
  end
end
