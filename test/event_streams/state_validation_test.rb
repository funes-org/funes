require "test_helper"
require "minitest/spec"

class StateValidationTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  module Events4CurrentTest
    class Add < Funes::Event; attribute :value, :integer; end
    class Start < Funes::Event; attribute :value, :integer; end
  end

  class ConsistencyModel
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :realized_value, :integer
    validates :realized_value, numericality: { greater_than_or_equal_to: 0 }
  end

  class ConsistencyProjection < Funes::Projection
    materialization_model ConsistencyModel

    initial_state do |materialization_model|
      materialization_model.new
    end

    interpretation_for Events4CurrentTest::Start do |state, event|
      state.assign_attributes(realized_value: event.value)
      state
    end

    interpretation_for Events4CurrentTest::Add do |state, event|
      state.assign_attributes(realized_value: state.realized_value + event.value)
      state
    end
  end

  class SubjectEventStream < Funes::EventStream
    consistency_projection ConsistencyProjection
  end

  describe "when the state validation fails" do
    describe "on a fresh stream" do
      event_that_led_to_invalid_state = Events4CurrentTest::Start.new(value: -1)

      it "does not persist the new event in the event log" do
        assert_no_difference -> { Funes::EventEntry.count } do
          SubjectEventStream.for("hadouken").append!(event_that_led_to_invalid_state)
        end
      end

      describe "error management" do
        before do
          SubjectEventStream.for("hadouken").append!(event_that_led_to_invalid_state)
        end

        it { assert_equal(event_that_led_to_invalid_state.errors.size, 1) }
        it { assert_equal(event_that_led_to_invalid_state.state_errors.size, 1) }

        it "injects proper information about the state error" do
          assert_equal event_that_led_to_invalid_state.state_errors.first.attribute, :realized_value
          assert_equal event_that_led_to_invalid_state.state_errors.first.message, "must be greater than or equal to 0"
        end

        it "keeps the event's own errors empty" do
          assert_empty event_that_led_to_invalid_state.own_errors
        end

        it "keeps regular `errors.full_messages` method functional" do
          assert_nothing_raised do
            event_that_led_to_invalid_state.errors.full_messages
          end
        end
      end
    end

    describe "on a previously created stream" do
      before do
        SubjectEventStream.for("hadouken").append!(Events4CurrentTest::Start.new(value: 0))
      end

      event_that_led_to_invalid_state = Events4CurrentTest::Add.new(value: -1)

      it "does not persist the event in the event log" do
        assert_no_difference -> { Funes::EventEntry.count } do
          SubjectEventStream.for("hadouken").append!(event_that_led_to_invalid_state)
        end
      end

      describe "error management" do
        before do
          SubjectEventStream.for("hadouken").append!(event_that_led_to_invalid_state)
        end

        it { assert_equal(event_that_led_to_invalid_state.errors.size, 1) }
        it { assert_equal(event_that_led_to_invalid_state.state_errors.size, 1) }

        it "injects proper information about the state error" do
          assert_equal event_that_led_to_invalid_state.state_errors.first.attribute, :realized_value
          assert_equal event_that_led_to_invalid_state.state_errors.first.message, "must be greater than or equal to 0"
        end

        it "keeps the event's own errors empty" do
          assert_empty event_that_led_to_invalid_state.own_errors
        end

        it "keeps regular `errors.full_messages` method functional" do
          assert_nothing_raised do
            event_that_led_to_invalid_state.errors.full_messages
          end
        end
      end
    end
  end

  describe "when the state validation does not fail" do
    valid_event = Events4CurrentTest::Start.new(value: 0)

    it "persists the new event in the event log" do
      assert_difference -> { Funes::EventEntry.count }, 1 do
        SubjectEventStream.for("hadouken").append!(valid_event)
      end
    end

    describe "error management" do
      before do
        SubjectEventStream.for("hadouken").append!(valid_event)
      end

      it { assert_empty valid_event.state_errors }
      it { assert_empty valid_event.errors }
    end
  end
end
