require "test_helper"
require "minitest/spec"

class EventStreamTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  module Events4CurrentTest
    class Add < Funes::Event; attribute :value, :integer; end
    class Start < Funes::Event; attribute :value, :integer; end
  end

  module BasicInterpretations4CurrentTest
    def self.included(base)
      base.class_eval do
        initial_state do |materialization_model|
          materialization_model.new
        end

        interpretation_for Events4CurrentTest::Start do |state, event|
          state.assign_attributes(value: event.value)
          state
        end

        interpretation_for Events4CurrentTest::Add do |state, event|
          state.assign_attributes(value: state.value + event.value)
          state
        end
      end
    end
  end

  activemodel_materialization = Class.new do
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :value, :integer
  end

  consistency_projection = Class.new(Funes::Projection) do
    materialization_model activemodel_materialization

    include BasicInterpretations4CurrentTest
  end

  transactional_projection = Class.new(Funes::Projection) do
    materialization_model UnitTests::Materialization

    include BasicInterpretations4CurrentTest
  end

  event_stream = Class.new(Funes::EventStream) do
    consistency_projection consistency_projection
    add_transactional_projection transactional_projection
  end

  events = [ Events4CurrentTest::Start.new(value: 0),
             Events4CurrentTest::Add.new(value: 1) ]

  describe "append! method" do
    describe "the happy path" do
      describe "with a fresh event stream" do
        it "persists the event to the event log" do
          assert_difference -> { Funes::EventEntry.count }, 1 do
            event_stream.for("hadouken").append! events.first
          end
        end

        it "adds the transactional projection to the database" do
          assert_difference -> { UnitTests::Materialization.count }, 1 do
            event_stream.for("hadouken").append! events.first
          end

          assert_equal UnitTests::Materialization.all.first.value, 0
        end
      end

      describe "with a previously created event stream" do
        before do
          event_stream.for("hadouken").append! events.first
        end

        it "persists the event to the event log" do
          assert_difference -> { Funes::EventEntry.count }, 1 do
            event_stream.for("hadouken").append! events.second
          end
        end

        it "updates the existent stream's transactional projection record" do
          assert_no_difference -> { UnitTests::Materialization.count } do
            event_stream.for("hadouken").append! events.second
          end

          assert_equal UnitTests::Materialization.all.first.value, 1
        end
      end
    end

    describe "when the event validation fails" do
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

      describe "on a fresh stream" do
        it "does not persist the event in the event log" do
          invalid_event = Events4CurrentTest::Start.new(value: -1)

          assert_no_difference -> { Funes::EventEntry.count } do
            event_stream.for("hadouken").append!(invalid_event)
          end

          assert_equal invalid_event.errors.size, 1
          assert_equal invalid_event.errors.first.attribute, :value
          assert_equal invalid_event.errors.first.message, "must be greater than or equal to 0"

          assert invalid_event.own_errors.any?
          assert invalid_event.state_errors.empty?
        end
      end

      describe "on a previously created stream" do
        before do
          event_stream.for("hadouken").append! events.first
        end

        it "does not persist the event in the event log" do
          invalid_event = Events4CurrentTest::Add.new(value: -1)

          assert_no_difference -> { Funes::EventEntry.count } do
            event_stream.for("hadouken").append!(invalid_event)
          end

          assert_equal invalid_event.errors.size, 1
          assert_equal invalid_event.errors.first.attribute, :value
          assert_equal invalid_event.errors.first.message, "must be greater than or equal to 0"

          assert invalid_event.own_errors.any?
          assert invalid_event.state_errors.empty?
        end
      end
    end
  end
end
