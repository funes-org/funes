require "test_helper"
require "minitest/spec"

class EventValidationTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  module Events4CurrentTest
    class Add < Funes::Event
      attribute :value, :integer
      validates :value, numericality: { greater_than_or_equal_to: 0 }
    end

    class Start < Funes::Event
      attribute :value, :integer
      validates :value, numericality: { greater_than_or_equal_to: 0 }
    end
  end

  class ConsistencyModel
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :realized_value, :integer
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

  describe "when the event validation fails" do
    describe "on a fresh stream" do
      invalid_event = Events4CurrentTest::Start.new(value: -1)

      it "does not persist the new event in the event log" do
        assert_no_difference -> { Funes::EventEntry.count } do
          SubjectEventStream.for("hadouken").append!(invalid_event)
        end
      end

      describe "error management" do
        before do
          SubjectEventStream.for("hadouken").append!(invalid_event)
        end

        it { assert_equal(invalid_event.errors.size, 1) }
        it { assert_equal(invalid_event.own_errors.size, 1) }

        it "injects proper information about the event error" do
          assert_equal invalid_event.own_errors.first.attribute, :value
          assert_equal invalid_event.own_errors.first.message, "must be greater than or equal to 0"
        end

        it "keeps the state's errors empty" do
          assert_empty invalid_event.state_errors
        end

        it "keeps regular `errors.full_messages` method functional" do
          assert_nothing_raised do
            invalid_event.errors.full_messages
          end
        end
      end
    end

    describe "on a previously created stream" do
      before do
        SubjectEventStream.for("hadouken").append!(Events4CurrentTest::Start.new(value: 0))
      end

      invalid_event = Events4CurrentTest::Add.new(value: -1)

      it "does not persist the new event in the event log" do
        assert_no_difference -> { Funes::EventEntry.count } do
          SubjectEventStream.for("hadouken").append!(invalid_event)
        end
      end

      describe "error management" do
        before do
          SubjectEventStream.for("hadouken").append!(invalid_event)
        end

        it { assert_equal(invalid_event.errors.size, 1) }
        it { assert_equal(invalid_event.own_errors.size, 1) }

        it "injects proper information about the event error" do
          assert_equal invalid_event.own_errors.first.attribute, :value
          assert_equal invalid_event.own_errors.first.message, "must be greater than or equal to 0"
        end

        it "keeps the state's errors empty" do
          assert_empty invalid_event.state_errors
        end

        it "keeps regular `errors.full_messages` method functional" do
          assert_nothing_raised do
            invalid_event.errors.full_messages
          end
        end
      end
    end
  end

  describe "when the event validation does not fail" do
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

      it { assert_empty valid_event.own_errors }
      it { assert_empty valid_event.errors }
    end
  end
end
