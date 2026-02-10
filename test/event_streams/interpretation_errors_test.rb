require "test_helper"
require "minitest/spec"

class InterpretationErrorsTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  module Events4CurrentTest
    class Start < Funes::Event
      attribute :value, :integer
    end

    class Add < Funes::Event
      attribute :value, :integer
    end
  end

  class ConsistencyModel
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :realized_value, :integer
  end

  class ProjectionWithInterpretationErrors < Funes::Projection
    materialization_model ConsistencyModel

    initial_state do |materialization_model|
      materialization_model.new
    end

    interpretation_for Events4CurrentTest::Start do |state, event|
      event.errors.add(:base, "Cannot start with negative value") if event.value.negative?
      state.assign_attributes(realized_value: event.value.abs)
      state
    end

    interpretation_for Events4CurrentTest::Add do |state, event|
      event.errors.add(:value, "exceeds limit") if event.value.abs > 100
      event.errors.add(:base, "negative additions not allowed") if event.value.negative?
      state.assign_attributes(realized_value: state.realized_value + event.value.abs)
      state
    end
  end

  class SubjectEventStream < Funes::EventStream
    consistency_projection ProjectionWithInterpretationErrors
  end

  class TransactionalProjectionEventStream < Funes::EventStream
    add_transactional_projection ProjectionWithInterpretationErrors
  end

  describe "logging of ineffective interpretation errors" do
    original_warn = Rails.logger.method(:warn)

    teardown do
      Rails.logger.define_singleton_method(:warn, original_warn)
    end

    describe "when errors are added in a non-consistency projection" do
      it "logs a warning and discards the errors" do
        TransactionalProjectionEventStream.for("warn-test").append(Events4CurrentTest::Start.new(value: 5))

        warnings = []
        Rails.logger.define_singleton_method(:warn) { |msg| warnings << msg }

        TransactionalProjectionEventStream.for("warn-test").append(Events4CurrentTest::Add.new(value: -10))

        assert warnings.any? { |msg| msg.include?("[Funes]") },
          "Expected a warning to be logged for errors in non-consistency projection"
        assert warnings.any? { |msg| msg.include?("negative additions not allowed") },
          "logs the proper error message"
      end
    end

    describe "when errors are added in a consistency projection" do
      it "does not log a warning" do
        warnings = []
        Rails.logger.define_singleton_method(:warn) { |msg| warnings << msg }

        SubjectEventStream.for("no-warn-test").append(Events4CurrentTest::Start.new(value: -5))

        assert warnings.none? { |msg| msg.include?("[Funes]") },
          "Expected no warning to be logged for errors in a consistency projection"
      end
    end
  end

  describe "when interpretation errors are added" do
    describe "on a fresh stream" do
      invalid_event = Events4CurrentTest::Start.new(value: -5)

      it "does not persist the event" do
        assert_no_difference -> { Funes::EventEntry.count } do
          SubjectEventStream.for("hadouken").append(invalid_event)
        end
      end

      describe "error management" do
        before do
          SubjectEventStream.for("hadouken").append(invalid_event)
        end

        it "makes valid? return false" do
          refute invalid_event.valid?
        end

        it "makes invalid? return true" do
          assert invalid_event.invalid?
        end

        it "keeps state_errors empty" do
          assert_empty invalid_event.state_errors
        end

        it "includes interpretation errors in own_errors" do
          assert_equal invalid_event.own_errors.messages, { base: [ "Cannot start with negative value" ] }
        end
      end
    end

    describe "on a previously created stream" do
      before do
        SubjectEventStream.for("hadouken").append(Events4CurrentTest::Start.new(value: 5))
      end

      invalid_event = Events4CurrentTest::Add.new(value: 200)

      it "does not persist the new invalid event" do
        assert_no_difference -> { Funes::EventEntry.count } do
          SubjectEventStream.for("hadouken").append(invalid_event)
        end
      end

      describe "error management" do
        before do
          SubjectEventStream.for("hadouken").append(invalid_event)
        end

        it "populates interpretation_errors with custom attribute" do
          assert_equal 1, invalid_event._interpretation_errors.size
          assert_equal :value, invalid_event._interpretation_errors.first.attribute
          assert_equal "exceeds limit", invalid_event._interpretation_errors.first.message
        end

        it "makes valid? return false" do
          refute invalid_event.valid?
        end
      end
    end
  end
end
