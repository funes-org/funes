require "test_helper"
require "minitest/spec"

class ProjectionTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  class LocalUnknownDepositEvent < Funes::Event; end

  describe "function/interpretation management" do
    test "projections persist their interpretation as Proc objects" do
      assert Examples::Deposit::ConsistencyProjection
               .instance_variable_get(:@interpretations)[Examples::DepositEvents::Created].is_a?(Proc)
      assert Examples::Deposit::ConsistencyProjection
               .instance_variable_get(:@interpretations)[Examples::DepositEvents::Withdrawn].is_a?(Proc)
    end

    test "projections return nothing while accessing events without interpretation set" do
      assert_nil Examples::Deposit::ConsistencyProjection
                   .instance_variable_get(:@interpretations)[LocalUnknownDepositEvent]
    end
  end

  describe "materialization model missing management" do
    it "raises UnknownMaterializationModel on materialization" do
      assert_raises Funes::UnknownMaterializationModel do
        Class.new(Funes::Projection)
             .materialize!([ Examples::DepositEvents::Created
                               .new(value: 100, effective_date: Date.today) ], "some-id")
      end
    end

    it "raises UnknownMaterializationModel on process_events" do
      assert_raises Funes::UnknownMaterializationModel do
        Class.new(Funes::Projection)
             .process_events([ Examples::DepositEvents::Created
                               .new(value: 100, effective_date: Date.today) ])
      end
    end
  end

  describe "accumulation of state interpretations through #process_events" do
    it "accumulates state changes correctly when processing a sequence of events" do
      assert_equal 50, Examples::Deposit::ConsistencyProjection
                         .process_events([ Examples::DepositEvents::Created.new(value: 100, effective_date: Date.today),
                                           Examples::DepositEvents::Withdrawn.new(amount: 30, effective_date: Date.today),
                                           Examples::DepositEvents::Withdrawn.new(amount: 20, effective_date: Date.today) ])
                         .balance
    end

    it "ignores unknown events while continuing to process valid events in the sequence" do
      assert_equal 70, Examples::Deposit::ConsistencyProjection
                         .process_events([ Examples::DepositEvents::Created.new(value: 100, effective_date: Date.today),
                                          LocalUnknownDepositEvent.new,
                                          Examples::DepositEvents::Withdrawn.new(amount: 30, effective_date: Date.today) ])
                         .balance
    end
  end

  describe "exceptions management while interpreting unknown events" do
    it "silently ignores unknown events by default without raising exceptions" do
      assert_nothing_raised do
        Examples::Deposit::ConsistencyProjection
          .process_events([ Examples::DepositEvents::Created.new(value: 100, effective_date: Date.today),
                           LocalUnknownDepositEvent.new ])
      end
    end

    it "raises an exception when processing unknown events with strict configuration enabled" do
      local_deposit_projection_that_does_not_ignore_unknown_events = Class.new(Funes::Projection) do
        raise_on_unknown_events
        materialization_model Examples::Deposit::Consistency
        interpretation_for Examples::DepositEvents::Created do |state, _event, _at| state end
        interpretation_for Examples::DepositEvents::Withdrawn do |state, _event, _at| state end
      end

      assert_raises Funes::UnknownEvent do
        local_deposit_projection_that_does_not_ignore_unknown_events
          .process_events([ Examples::DepositEvents::Created.new(value: 100, effective_date: Date.today),
                           LocalUnknownDepositEvent.new ])
      end
    end
  end

  describe "temporal argument (at) in process_events" do
    class TemporalMaterializationForInspection
      include ActiveModel::Model
      include ActiveModel::Attributes

      attribute :initial_state_temporal_arg, :datetime
      attribute :event_temporal_arg, :datetime
      attribute :final_state_temporal_arg, :datetime
    end

    class LocalProjectionForInspection < Funes::Projection
      materialization_model TemporalMaterializationForInspection

      initial_state do |materialization_model_class, at|
        materialization_model_class.new(initial_state_temporal_arg: at)
      end

      interpretation_for Examples::DepositEvents::Created do |state, _event, at|
        state.assign_attributes(event_temporal_arg: at); state
      end

      final_state do |state, at|
        state.assign_attributes(final_state_temporal_arg: at); state
      end
    end

    describe "initial and final interpretations" do
      describe "when the `at` is not informed" do
        it "interprets the initial state with `Time.current` as `at`" do
          freeze_time do
            assert_equal Time.current, LocalProjectionForInspection
                                         .process_events([ Examples::DepositEvents::Created
                                                             .new(value: 1, effective_date: Date.today) ])
                                         .initial_state_temporal_arg
          end
        end

        it "interprets the final state with `Time.current` as `at`" do
          freeze_time do
            assert_equal Time.current, LocalProjectionForInspection
                                         .process_events([ Examples::DepositEvents::Created
                                                             .new(value: 1, effective_date: Date.today) ])
                                         .final_state_temporal_arg
          end
        end
      end

      describe "when the `at` is informed" do
        at_value = Date.today + 1.year

        it "interprets the initial state with the informed `at`" do
          assert_equal at_value, LocalProjectionForInspection
                                   .process_events([ Examples::DepositEvents::Created
                                                       .new(value: 1, effective_date: Date.today) ],
                                                   at: at_value)
                                   .initial_state_temporal_arg
        end

        it "interprets the final state with the informed `at`" do
          assert_equal at_value, LocalProjectionForInspection
                                   .process_events([ Examples::DepositEvents::Created
                                                       .new(value: 1, effective_date: Date.tomorrow) ],
                                                   at: at_value)
                                   .final_state_temporal_arg
        end
      end
    end

    describe "event interpretation" do
      describe "when the event is not persisted" do
        at_value = Date.today + 1.year

        it "interprets the event using the informed `at`" do
          assert_equal at_value, LocalProjectionForInspection
                                   .process_events([ Examples::DepositEvents::Created
                                                       .new(value: 1, effective_date: Date.tomorrow) ],
                                                   at: at_value)
                                   .event_temporal_arg
        end
      end

      describe "when the event is persisted" do
        it "interprets the event using its occurrence data instead of the informed `at`" do
          at_value = Date.today + 1.year
          event_effective_date = Time.current
          persisted_event = Funes::EventEntry
                              .create!(klass: "Examples::DepositEvents::Created", created_at: Time.current,
                                       occurred_at: event_effective_date, idx: "some-id",
                                       props: { value: 1, effective_date: event_effective_date.to_date })
                              .to_klass_instance

          assert_equal event_effective_date, LocalProjectionForInspection
                                               .process_events([ persisted_event ], at: at_value)
                                               .event_temporal_arg
        end
      end
    end
  end

  describe "persistence management when the materialization model is an ActiveRecord subclass" do
    let(:today) { Date.today }
    let(:events_coll) { [ Examples::DepositEvents::Created.new(value: 100, effective_date: today),
                           Examples::DepositEvents::Withdrawn.new(amount: 30, effective_date: today),
                           Examples::DepositEvents::Withdrawn.new(amount: 20, effective_date: today) ] }

    describe "materialization behavior" do
      describe "when the materialization model is an Active model" do
        it "returns an instance of the materialization model" do
          materialized_return = Examples::Deposit::ConsistencyProjection
                                  .materialize!(events_coll, "some-id", at: today)

          assert_instance_of Examples::Deposit::Consistency, materialized_return
        end


        it "calls process_events but does not call persist_based_on! to persist it in the database" do
          process_events_called = false
          persist_called = false

          spy_class = Class.new(Funes::Projection) do
            @materialization_model = Examples::Deposit::ConsistencyProjection
                                       .instance_variable_get(:@materialization_model)
            @interpretations = Examples::Deposit::ConsistencyProjection.instance_variable_get(:@interpretations)

            define_method(:process_events) { |*a, **kw| process_events_called = true; super(*a, **kw) }
            define_method(:persist_based_on!) { |*| persist_called = true }
          end

          spy_class.materialize!(events_coll, "some-id")

          assert process_events_called
          refute persist_called
        end
      end

      describe "when the materialization model is an ActiveRecord subclass" do
        it "returns an instance of the materialization model" do
          materialized_return = Examples::Deposit::SnapshotProjection
                                  .materialize!(events_coll, "some-id", at: today)

          assert_instance_of Examples::Deposit::Snapshot, materialized_return
        end

        it "creates the expected record in the database" do
          assert_difference -> { Examples::Deposit::Snapshot.count }, 1 do
            Examples::Deposit::SnapshotProjection.materialize!(events_coll, "some-id", at: today)
          end
          assert Examples::Deposit::Snapshot.find("some-id")
        end

        describe "when a record of the materialization is already persisted" do
          it "does not create a duplicate record when one already exists" do
            Examples::Deposit::SnapshotProjection.materialize!(events_coll, "some-id", at: today)

            assert_no_difference -> { Examples::Deposit::Snapshot.count } do
              Examples::Deposit::SnapshotProjection.materialize!(events_coll, "some-id", at: today)
            end
          end

          it "updates the previously persisted record when the computed data changes" do
            Examples::Deposit::SnapshotProjection.materialize!(events_coll.take(2), "some-id", at: today)
            previous_snapshot = Examples::Deposit::Snapshot.find("some-id")
            Examples::Deposit::SnapshotProjection.materialize!(events_coll, "some-id", at: today)
            posterior_snapshot = Examples::Deposit::Snapshot.find("some-id")

            assert_equal 70, previous_snapshot.balance
            assert_equal 50, posterior_snapshot.balance
          end
        end
      end
    end
  end
end
