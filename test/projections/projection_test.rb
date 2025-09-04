require "test_helper"
require "minitest/spec"

class ProjectionTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  module Events4CurrentTest
    class Add < Funes::Event; attribute :value, :integer; end
    class Start < Funes::Event; attribute :value, :integer; end
    class Unknown < Funes::Event; end
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

  basic_projection = Class.new(Funes::Projection) do
    materialization_model activemodel_materialization

    include BasicInterpretations4CurrentTest
  end

  basic_projection_without_materialization_model = Class.new(Funes::Projection) do
    include BasicInterpretations4CurrentTest
  end

  describe "function management" do
    it "sets event interpretations properly as Proc objects" do
      assert basic_projection.instance_variable_get(:@interpretations)[Events4CurrentTest::Start].is_a?(Proc)
      assert basic_projection.instance_variable_get(:@interpretations)[Events4CurrentTest::Add].is_a?(Proc)
    end

    it "returns nil instead of a Proc when accessing an event without defined interpretation" do
      # assert basic_projection.interpretations[Events4CurrentTest::Unknown].nil?
      assert basic_projection.instance_variable_get(:@interpretations)[Events4CurrentTest::Unknown].nil?
    end
  end

  describe "accumulation of state interpretations through #process_events" do
    it "accumulates state changes correctly when processing a sequence of events" do
      state = basic_projection.process_events([ Events4CurrentTest::Start.new(value: 5),
                                                Events4CurrentTest::Add.new(value: 4),
                                                Events4CurrentTest::Add.new(value: 2) ],
                                              Time.current)
      assert_equal 11, state.value
    end

    it "ignores unknown events while continuing to process valid events in the sequence" do
      state = basic_projection.process_events([ Events4CurrentTest::Start.new(value: 5),
                                                Events4CurrentTest::Unknown.new,
                                                Events4CurrentTest::Add.new(value: 2) ],
                                              Time.current)
      assert_equal 7, state.value
    end
  end

  describe "exceptions management while interpreting unknown events" do
    it "silently ignores unknown events by default without raising exceptions" do
      assert_nothing_raised do
        basic_projection.process_events([ Events4CurrentTest::Start.new(value: 5),
                                          Events4CurrentTest::Unknown.new ],
                                        Time.current)
      end
    end

    it "raises an exception when processing unknown events with strict configuration enabled" do
      projection_that_does_not_ignore_unknown_events = Class.new(Funes::Projection) do
        raise_on_unknown_events
        materialization_model activemodel_materialization

        include BasicInterpretations4CurrentTest
      end

      assert_raises Funes::UnknownEvent do
        projection_that_does_not_ignore_unknown_events.process_events([ Events4CurrentTest::Start.new(value: 5),
                                                                        Events4CurrentTest::Unknown.new ],
                                                                      Time.current)
      end
    end
  end

  describe "persistence management" do
    projection_with_activemodel_as_materialization_model = Class.new(Funes::Projection) do
      materialization_model activemodel_materialization

      include BasicInterpretations4CurrentTest
    end

    projection_with_activerecord_as_materialization_model = Class.new(Funes::Projection) do
      materialization_model UnitTests::Materialization

      include BasicInterpretations4CurrentTest
    end

    describe "materialization behavior" do
      events_log = [ Events4CurrentTest::Start.new(value: 5),
                     Events4CurrentTest::Add.new(value: 4),
                     Events4CurrentTest::Add.new(value: 2) ]

      describe "when there is no materialization model set" do
        it "raises UnknownMaterializationModel when no materialization model is set" do
          assert_raises Funes::UnknownMaterializationModel do
            basic_projection_without_materialization_model.materialize!(events_log, "some-id", Time.current)
          end
        end
      end

      describe "when the materialization model is an Active model" do
        it "returns an instance with the computed attribute values" do
          materialized_return = projection_with_activemodel_as_materialization_model
                                  .materialize!(events_log, "some-id", Time.current)

          assert_instance_of activemodel_materialization, materialized_return
          assert_equal materialized_return.value, 11
        end
      end

      describe "when the materialization model is an ActiveRecord subclass" do
        it "returns an instance of the materialization model" do
          materialized_return = projection_with_activerecord_as_materialization_model
                                  .materialize!(events_log, "some-id", Time.current)

          assert_instance_of UnitTests::Materialization, materialized_return
        end

        it "creates the expected record in the database" do
          assert_difference -> { UnitTests::Materialization.count }, 1 do
            projection_with_activerecord_as_materialization_model.materialize!(events_log, "some-id", Time.current)
          end
          assert UnitTests::Materialization.find_by(idx: "some-id")
        end

        it "persists and returns the materialized data based on the projection computation" do
          projection_with_activerecord_as_materialization_model.materialize!(events_log, "some-id", Time.current)

          assert_equal UnitTests::Materialization.find_by(idx: "some-id").values_at(:idx, :value), [ "some-id", 11 ]
        end

        describe "when a record of the materialization is already persisted" do
          it "does not create a duplicate record when one already exists" do
            projection_with_activerecord_as_materialization_model.materialize!(events_log, "some-id", Time.current)

            assert_no_difference -> { UnitTests::Materialization.count } do
              projection_with_activerecord_as_materialization_model.materialize!(events_log, "some-id", Time.current)
            end
          end

          it "updates the previously persisted record when the computed data changes" do
            projection_with_activerecord_as_materialization_model.materialize!(events_log.take(2), "some-id", Time.current)
            assert_equal UnitTests::Materialization.find_by(idx: "some-id").values_at(:idx, :value), [ "some-id", 9 ]

            projection_with_activerecord_as_materialization_model.materialize!(events_log, "some-id", Time.current)
            assert_equal UnitTests::Materialization.find_by(idx: "some-id").values_at(:idx, :value), [ "some-id", 11 ]
          end
        end
      end
    end
  end
end
