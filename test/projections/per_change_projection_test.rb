require "test_helper"
require "minitest/spec"

class PerChangeProjectionTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  let(:today) { Date.today }
  let(:events_coll) do
    [ Examples::DepositEvents::Created.new(value: 100, effective_date: today),
      Examples::DepositEvents::Withdrawn.new(amount: 30, effective_date: today),
      Examples::DepositEvents::Withdrawn.new(amount: 20, effective_date: today) ]
  end

  describe "persists_per_change DSL" do
    it "flips the projection into per-change mode" do
      klass = Class.new(Funes::Projection) do
        materialization_model Examples::Deposit::History
        persists_per_change
      end

      assert klass.instance_variable_get(:@persists_per_change)
    end

    it "regular projections are not affected" do
      assert_nil Examples::Deposit::SnapshotProjection.instance_variable_get(:@persists_per_change)
    end
  end

  describe "guard rail" do
    it "raises when the materialization model is not ActiveRecord-backed" do
      klass = Class.new(Funes::Projection) do
        materialization_model Examples::Deposit::Consistency
        persists_per_change
        interpretation_for Examples::DepositEvents::Created do |state, _event, _at| state end
      end

      assert_raises Funes::InvalidPerChangeMaterializationTable do
        klass.materialize!([ Examples::DepositEvents::Created.new(value: 100, effective_date: today) ], "some-id")
      end
    end

    it "raises when the materialization table has no `version` column" do
      klass = Class.new(Funes::Projection) do
        materialization_model Examples::Deposit::Snapshot
        persists_per_change
        interpretation_for Examples::DepositEvents::Created do |state, event, at|
          state.assign_attributes(original_value: event.value, balance: event.value, created_at: at, status: :active)
          state
        end
      end

      assert_raises Funes::InvalidPerChangeMaterializationTable do
        klass.materialize!([ Examples::DepositEvents::Created.new(value: 100, effective_date: today) ], "some-id")
      end
    end
  end

  describe "persistence" do
    it "produces one row per interpreted event, keyed by event position" do
      Examples::Deposit::HistoryProjection.materialize!(events_coll, "some-id", at: today)

      rows = Examples::Deposit::History.where(idx: "some-id").order(:version).to_a

      assert_equal 3, rows.size
      assert_equal [ "1", "2", "3" ], rows.map(&:version)
    end

    it "accumulates state correctly across versions" do
      Examples::Deposit::HistoryProjection.materialize!(events_coll, "some-id", at: today)

      rows = Examples::Deposit::History.where(idx: "some-id").order(:version).to_a

      assert_equal 100, rows[0].balance
      assert_equal 70,  rows[1].balance
      assert_equal 50,  rows[2].balance
    end

    it "skips events without an interpretation (no row at that position)" do
      unknown_event_class = Class.new(Funes::Event)
      mixed = [ Examples::DepositEvents::Created.new(value: 100, effective_date: today),
                unknown_event_class.new,
                Examples::DepositEvents::Withdrawn.new(amount: 30, effective_date: today) ]

      Examples::Deposit::HistoryProjection.materialize!(mixed, "some-id", at: today)

      versions = Examples::Deposit::History.where(idx: "some-id").order(:version).pluck(:version)
      assert_equal [ "1", "3" ], versions
    end

    it "does not write a :final row when final_state is not declared" do
      Examples::Deposit::HistoryProjection.materialize!(events_coll, "some-id", at: today)

      assert_nil Examples::Deposit::History.find_by(idx: "some-id", version: "final")
    end

    it "writes a :final row when final_state is declared" do
      klass = Class.new(Funes::Projection) do
        materialization_model Examples::Deposit::History
        persists_per_change

        interpretation_for Examples::DepositEvents::Created do |state, event, _at|
          state.assign_attributes(balance: event.value); state
        end
        interpretation_for Examples::DepositEvents::Withdrawn do |state, event, _at|
          state.assign_attributes(balance: (state.balance || 0) - event.amount); state
        end
        final_state do |state, _at|
          state
        end
      end

      klass.materialize!(events_coll, "some-id", at: today)

      final_row = Examples::Deposit::History.find_by(idx: "some-id", version: "final")
      assert final_row
      assert_equal 50, final_row.balance
    end

    it "returns the materialized model instance reflecting the last state" do
      returned = Examples::Deposit::HistoryProjection.materialize!(events_coll, "some-id", at: today)

      assert_instance_of Examples::Deposit::History, returned
      assert_equal 50, returned.balance
    end
  end

  describe "re-projection" do
    it "is idempotent when re-run with the same events" do
      Examples::Deposit::HistoryProjection.materialize!(events_coll, "some-id", at: today)
      first_count = Examples::Deposit::History.where(idx: "some-id").count

      Examples::Deposit::HistoryProjection.materialize!(events_coll, "some-id", at: today)
      assert_equal first_count, Examples::Deposit::History.where(idx: "some-id").count
    end

    it "leaves no stale rows when the projection later drops an interpretation" do
      Examples::Deposit::HistoryProjection.materialize!(events_coll, "some-id", at: today)
      assert_equal 3, Examples::Deposit::History.where(idx: "some-id").count

      limited_klass = Class.new(Funes::Projection) do
        materialization_model Examples::Deposit::History
        persists_per_change

        interpretation_for Examples::DepositEvents::Created do |state, event, _at|
          state.assign_attributes(balance: event.value); state
        end
      end

      limited_klass.materialize!(events_coll, "some-id", at: today)

      versions = Examples::Deposit::History.where(idx: "some-id").order(:version).pluck(:version)
      assert_equal [ "1" ], versions
    end

    it "isolates writes per idx — other idx rows are untouched" do
      Examples::Deposit::HistoryProjection.materialize!(events_coll, "some-id", at: today)
      Examples::Deposit::HistoryProjection.materialize!(events_coll, "other-id", at: today)

      Examples::Deposit::HistoryProjection.materialize!(events_coll.take(1), "some-id", at: today)

      assert_equal 1, Examples::Deposit::History.where(idx: "some-id").count
      assert_equal 3, Examples::Deposit::History.where(idx: "other-id").count
    end
  end

  describe "atomicity" do
    it "rolls back the entire write when a snapshot is invalid" do
      Examples::Deposit::HistoryProjection.materialize!(events_coll, "some-id", at: today)
      baseline = Examples::Deposit::History.where(idx: "some-id").order(:version).to_a

      invalid_klass = Class.new(Funes::Projection) do
        materialization_model Examples::Deposit::History
        persists_per_change

        interpretation_for Examples::DepositEvents::Created do |state, event, _at|
          state.assign_attributes(balance: event.value); state
        end
        interpretation_for Examples::DepositEvents::Withdrawn do |state, _event, _at|
          state.assign_attributes(balance: nil); state
        end
      end

      assert_raises ActiveRecord::RecordInvalid do
        invalid_klass.materialize!(events_coll, "some-id", at: today)
      end

      current = Examples::Deposit::History.where(idx: "some-id").order(:version).to_a
      assert_equal baseline.map(&:version), current.map(&:version)
      assert_equal baseline.map(&:balance), current.map(&:balance)
    end
  end
end
