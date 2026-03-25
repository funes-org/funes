require "test_helper"
require "minitest/spec"

class PersistProjectionJobTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  let(:idx) { "some-any-id" }

  before do
    now = Time.current
    Funes::EventEntry.create!(klass: "Examples::DepositEvents::Created", idx: idx, version: 1,
                              props: { value: 100, effective_date: now.to_date }, created_at: now, occurred_at: now)
  end

  describe "#perform" do
    describe "before any run" do
      it "the initial event is in the database" do
        assert Funes::EventEntry.exists?(idx: idx, klass: "Examples::DepositEvents::Created")
      end

      it "there are no related snapshots persisted" do
        refute Examples::Deposit::Snapshot.exists?(idx)
      end
    end

    describe "materialization and persistence when the event stream has a single event" do
      before { Funes::PersistProjectionJob.perform_now(idx, Examples::Deposit::SnapshotProjection) }

      it "persists the projection" do
        assert Examples::Deposit::Snapshot.exists?(idx)
      end

      it "persists the projection with the proper updated data" do
        assert_equal 100, Examples::Deposit::Snapshot.find(idx).balance
      end
    end

    describe "materialization and persistence when the event stream has multiple events" do
      before do
        Funes::EventEntry.create!(klass: "Examples::DepositEvents::Withdrawn", idx: idx, version: 2,
                                  props: { amount: 50, effective_date: Date.today }, occurred_at: Time.current)

        Funes::PersistProjectionJob.perform_now(idx, Examples::Deposit::SnapshotProjection)
      end

      it "keeps a single persisted projection" do
        assert_equal 1, Examples::Deposit::Snapshot.where(idx: idx).count
      end

      it "persists the projection with the proper updated data" do
        assert_equal 50, Examples::Deposit::Snapshot.find(idx).balance
      end
    end

    describe "materialization and persistence when there are materializations previously persisted" do
      before do
        Funes::PersistProjectionJob.perform_now(idx, Examples::Deposit::SnapshotProjection)
      end

      test "the previous materialization really is in the database" do
        assert_equal 100, Examples::Deposit::Snapshot.find(idx).balance
      end

      it "updates the previous materialization with the updated balance" do
        Funes::EventEntry.create!(klass: "Examples::DepositEvents::Withdrawn", idx: idx, version: 2,
                                  props: { amount: 50, effective_date: Date.today }, occurred_at: Time.current)
        Funes::PersistProjectionJob.perform_now(idx, Examples::Deposit::SnapshotProjection)

        assert_equal 50, Examples::Deposit::Snapshot.find(idx).balance
      end
    end

    describe "temporal event stream slicing" do
      before do
        ten_days_ahead = Time.current + 10.days
        Funes::EventEntry.create!(klass: "Examples::DepositEvents::Withdrawn", idx: idx, version: 2,
                                  props: { amount: 50, effective_date: ten_days_ahead.to_date },
                                  created_at: ten_days_ahead, occurred_at: ten_days_ahead)
      end

      describe "`as_of` information handling" do
        before { Funes::PersistProjectionJob.perform_now(idx, Examples::Deposit::SnapshotProjection,
                                                         Time.current + 5.days) }

        it "computes the events until the `as_of` point in time" do
          assert_equal 100, Examples::Deposit::Snapshot.find(idx).balance
        end
      end

      describe "`at` information handling" do
        before { Funes::PersistProjectionJob.perform_now(idx, Examples::Deposit::SnapshotProjection,
                                                         nil, Time.current + 5.days) }

        it "computes the events until the `at` point in time" do
          assert_equal 100, Examples::Deposit::Snapshot.find(idx).balance
        end
      end
    end
  end
end
