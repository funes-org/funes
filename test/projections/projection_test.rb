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
        set_interpretation_for Events4CurrentTest::Start do |_state, event|
          { value: event.value }
        end

        set_interpretation_for Events4CurrentTest::Add do |state, event|
          { value: state[:value] + event.value }
        end
      end
    end
  end

  basic_projection = Class.new(Funes::Projection) do
    include BasicInterpretations4CurrentTest
  end

  describe "function management" do
    it "sets event interpretations properly as Proc objects" do
      assert basic_projection.interpretations[Events4CurrentTest::Start].is_a?(Proc)
      assert basic_projection.interpretations[Events4CurrentTest::Add].is_a?(Proc)
    end

    it "returns nil instead of a Proc when accessing an event without defined interpretation" do
      assert basic_projection.interpretations[Events4CurrentTest::Unknown].nil?
    end
  end

  describe "accumulation of state interpretations through #process_events" do
    it "accumulates state changes correctly when processing a sequence of events" do
      state = basic_projection.process_events([ Events4CurrentTest::Start.new(value: 5),
                                                Events4CurrentTest::Add.new(value: 4),
                                                Events4CurrentTest::Add.new(value: 2) ])
      assert_equal 11, state[:value]
    end

    it "ignores unknown events while continuing to process valid events in the sequence" do
      state = basic_projection.process_events([ Events4CurrentTest::Start.new(value: 5),
                                                Events4CurrentTest::Unknown.new,
                                                Events4CurrentTest::Add.new(value: 2) ])
      assert_equal 7, state[:value]
    end
  end

  describe "exceptions management while interpreting unknown events" do
    it "silently ignores unknown events by default without raising exceptions" do
      assert_nothing_raised do
        basic_projection.process_events([ Events4CurrentTest::Start.new(value: 5),
                                          Events4CurrentTest::Unknown.new ])
      end
    end

    it "raises an exception when processing unknown events with strict configuration enabled" do
      projection_that_does_not_ignore_unknown_events = Class.new(Funes::Projection) do
        not_ignore_unknown_event_types

        include BasicInterpretations4CurrentTest
      end

      assert_raises Funes::UnknownEvent do
        projection_that_does_not_ignore_unknown_events.process_events([ Events4CurrentTest::Start.new(value: 5),
                                                                        Events4CurrentTest::Unknown.new ])
      end
    end
  end

  describe "persistence management" do
    activemodel_materialization = Class.new do
      include ActiveModel::Model
      include ActiveModel::Attributes

      attribute :value, :integer
    end

    projection_with_activemodel_as_materialization_model = Class.new(Funes::Projection) do
      set_materialization_model activemodel_materialization

      include BasicInterpretations4CurrentTest
    end

    projection_with_activerecord_as_materialization_model = Class.new(Funes::Projection) do
      set_materialization_model UnitTests::Materialization

      include BasicInterpretations4CurrentTest
    end

    describe "persistable?" do
      it "returns false for defaut projections - those without an informed materialization model" do
        assert_not basic_projection.persistable?
      end

      it "returns true when the materialization model is an ActiveRecord subclass" do
        assert projection_with_activerecord_as_materialization_model.persistable?
      end

      it "returns false when the materialization model is an ActiveModel" do
        assert_not projection_with_activemodel_as_materialization_model.persistable?
      end
    end

    describe "materialization behavior" do
      events_log = [ Events4CurrentTest::Start.new(value: 5),
                     Events4CurrentTest::Add.new(value: 4),
                     Events4CurrentTest::Add.new(value: 2) ]

      describe "when there is no materialization model set" do
        it "raises an exception" do
          assert_raises Funes::UnknownMaterializationModel do
            basic_projection.materialize!(events_log, "some-id")
          end
        end
      end

      describe "when the materialization model is an Active model" do
        it "returns an instance of it with the proper attribute values based on the projection computing" do
          materialized_return = projection_with_activemodel_as_materialization_model
                                  .materialize!(events_log, "some-id")

          assert_instance_of activemodel_materialization, materialized_return
          assert_equal materialized_return.value, 11
        end
      end

      describe "when the materialization model is an ActiveRecord subclass" do
        it "returns an instance with the correct model type" do
          materialized_return = projection_with_activerecord_as_materialization_model
                                  .materialize!(events_log, "some-id")

          assert_instance_of UnitTests::Materialization, materialized_return
        end

        it "creates the expected record in the database" do
          assert_difference -> { UnitTests::Materialization.count }, 1 do
            projection_with_activerecord_as_materialization_model.materialize!(events_log, "some-id")
          end
          assert UnitTests::Materialization.find_by(idx: "some-id")
        end

        it "persists and returns the data properly based on the projection computing" do
          projection_with_activerecord_as_materialization_model.materialize!(events_log, "some-id")

          assert_equal UnitTests::Materialization.find_by(idx: "some-id").values_at(:idx, :value), [ "some-id", 11 ]
        end

        describe "when a record of the materialization is already persisted" do
          it "does not create a new record for it" do
            projection_with_activerecord_as_materialization_model.materialize!(events_log, "some-id")

            assert_no_difference -> { UnitTests::Materialization.count } do
              projection_with_activerecord_as_materialization_model.materialize!(events_log, "some-id")
            end
          end

          it "updates the previously persisted record when the data changes" do
            projection_with_activerecord_as_materialization_model.materialize!(events_log.take(2), "some-id")
            assert_equal UnitTests::Materialization.find_by(idx: "some-id").values_at(:idx, :value), [ "some-id", 9 ]

            projection_with_activerecord_as_materialization_model.materialize!(events_log, "some-id")
            assert_equal UnitTests::Materialization.find_by(idx: "some-id").values_at(:idx, :value), [ "some-id", 11 ]
          end
        end
      end
    end
  end
end
