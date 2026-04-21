require "test_helper"
require "minitest/spec"

class AppendBangTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL
  include ActiveJob::TestHelper

  class EventStreamWithAsync < Funes::EventStream
    consistency_projection Examples::Deposit::ConsistencyProjection
    actual_time_attribute :effective_date

    add_transactional_projection Examples::Deposit::SnapshotProjection
    add_async_projection Examples::Deposit::LastActivityProjection
  end

  let(:idx) { "append-bang-#{SecureRandom.uuid}" }

  describe "when the append succeeds" do
    let(:event) { Examples::DepositEvents::Created.new(value: 42, effective_date: Date.today) }

    it "returns the event, persists it, and enqueues the async projection" do
      returned_event = nil

      assert_enqueued_with(job: Funes::PersistProjectionJob) do
        returned_event = EventStreamWithAsync.for(idx).append!(event)
      end

      assert_same event, returned_event
      assert event.persisted?
      assert_equal 1, Funes::EventEntry.where(idx: idx).count
      assert Examples::Deposit::Snapshot.exists?(idx)
    end
  end

  describe "when the event's own validation fails" do
    let(:invalid_event) { Examples::DepositEvents::Created.new(value: -1, effective_date: Date.today) }

    it "raises ActiveRecord::RecordInvalid, leaves it unpersisted, and enqueues nothing" do
      assert_no_enqueued_jobs do
        error = assert_raises(ActiveRecord::RecordInvalid) do
          EventStreamWithAsync.for(idx).append!(invalid_event)
        end

        assert_same invalid_event, error.record
        refute invalid_event.persisted?
        assert invalid_event.errors.any?
        refute Funes::EventEntry.exists?(idx: idx)
      end
    end
  end

  describe "when the consistency projection rejects the event" do
    let(:withdraw_exceeding_balance) { Examples::DepositEvents::Withdrawn.new(amount: 1_000, effective_date: Date.today) }

    before do
      EventStreamWithAsync
        .for(idx)
        .append!(Examples::DepositEvents::Created.new(value: 42, effective_date: Date.today))
    end

    it "raises ActiveRecord::RecordInvalid, leaves the event inspectable, and enqueues nothing" do
      assert_no_enqueued_jobs do
        error = assert_raises(ActiveRecord::RecordInvalid) do
          EventStreamWithAsync.for(idx).append!(withdraw_exceeding_balance)
        end

        assert_same withdraw_exceeding_balance, error.record
        refute withdraw_exceeding_balance.persisted?
        assert withdraw_exceeding_balance.errors.any?
      end
    end

    it "does not persist the event or touch materializations" do
      previous_snapshot = Examples::Deposit::Snapshot.find(idx)
      event_count_before = Funes::EventEntry.where(idx: idx).count

      assert_no_enqueued_jobs do
        assert_raises(ActiveRecord::RecordInvalid) do
          EventStreamWithAsync.for(idx).append!(withdraw_exceeding_balance)
        end
      end

      assert_equal event_count_before, Funes::EventEntry.where(idx: idx).count
      assert_equal previous_snapshot.attributes, Examples::Deposit::Snapshot.find(idx).attributes
    end
  end

  describe "when a version conflict races the insert" do
    let(:event) { Examples::DepositEvents::Created.new(value: 42, effective_date: Date.today) }

    before do
      travel_to(1.minute.from_now) do
        Funes::EventEntry.create!(klass: Examples::DepositEvents::Created.name, idx: idx, version: 1,
                                  props: { value: 100, effective_date: Date.today }, occurred_at: Time.current)
      end
    end

    it "raises ActiveRecord::RecordInvalid, surfaces the racing message, and enqueues nothing" do
      assert_no_enqueued_jobs do
        error = assert_raises(ActiveRecord::RecordInvalid) do
          EventStreamWithAsync.for(idx).append!(event)
        end

        assert_same event, error.record
        refute event.persisted?
        assert event.errors[:base].present?
        assert_equal 0, Examples::Deposit::Snapshot.where(idx: idx).count
      end
    end
  end

  describe "when a transactional projection fails on a database constraint" do
    let(:event) { Examples::DepositEvents::Created.new(value: 42, effective_date: Date.today) }

    it "re-raises the original database exception (record is the projection model, not the event)" do
      assert_no_enqueued_jobs do
        error = assert_raises(ActiveRecord::NotNullViolation) do
          SpecFailingExamples::SingleTransactionalProjection::DepositEventStream.for(idx).append!(event)
        end

        refute_kind_of ActiveRecord::RecordInvalid, error
        refute event.persisted?
        refute Funes::EventEntry.exists?(idx: idx)
      end
    end
  end

  describe "when a transactional projection fails AR validation" do
    let(:event) { Examples::DepositEvents::Created.new(value: 42, effective_date: Date.today) }

    it "re-raises ActiveRecord::RecordInvalid whose record is the projection materialization, not the event" do
      assert_no_enqueued_jobs do
        error = assert_raises(ActiveRecord::RecordInvalid) do
          SpecFailingExamples::SingleTransactionalProjection::DepositEventStreamWithValidationFailure.for(idx).append!(event)
        end

        refute_same event, error.record
        assert_kind_of Examples::Deposit::LastActivities, error.record
        refute event.persisted?
        refute Funes::EventEntry.exists?(idx: idx)
      end
    end
  end

  describe "when append! is wrapped in a user-opened ActiveRecord::Base.transaction" do
    let(:event) { Examples::DepositEvents::Created.new(value: 42, effective_date: Date.today) }
    let(:sibling_idx) { "sibling-#{SecureRandom.uuid}" }

    before do
      travel_to(1.minute.from_now) do
        Funes::EventEntry.create!(klass: Examples::DepositEvents::Created.name, idx: idx, version: 1,
                                  props: { value: 100, effective_date: Date.today }, occurred_at: Time.current)
      end
    end

    it "rolls back sibling writes and enqueues nothing when append! raises on version conflict" do
      assert_no_enqueued_jobs do
        assert_raises(ActiveRecord::RecordInvalid) do
          ActiveRecord::Base.transaction do
            Examples::Deposit::Snapshot.create!(idx: sibling_idx, created_at: Date.today,
                                                original_value: 10, balance: 10)
            EventStreamWithAsync.for(idx).append!(event)
          end
        end
      end

      refute Examples::Deposit::Snapshot.exists?(sibling_idx), "sibling write must be rolled back"
      refute event.persisted?
      assert event.errors[:base].present?
    end
  end

  describe "when two append! calls share a user-opened transaction" do
    let(:event_1) { Examples::DepositEvents::Created.new(value: 10, effective_date: Date.today) }
    let(:event_2) { Examples::DepositEvents::Created.new(value: 20, effective_date: Date.today) }
    let(:idx_1) { "two-append-a-#{SecureRandom.uuid}" }
    let(:idx_2) { "two-append-b-#{SecureRandom.uuid}" }

    before do
      travel_to(1.minute.from_now) do
        Funes::EventEntry.create!(klass: Examples::DepositEvents::Created.name, idx: idx_2, version: 1,
                                  props: { value: 100, effective_date: Date.today }, occurred_at: Time.current)
      end
    end

    it "rolls back the first append! and enqueues nothing when the second raises" do
      assert_no_enqueued_jobs do
        assert_raises(ActiveRecord::RecordInvalid) do
          ActiveRecord::Base.transaction do
            EventStreamWithAsync.for(idx_1).append!(event_1)
            EventStreamWithAsync.for(idx_2).append!(event_2)
          end
        end
      end

      refute Funes::EventEntry.exists?(idx: idx_1), "first event must be rolled back"
      refute event_1.persisted?
      refute event_2.persisted?
      assert event_2.errors[:base].present?
    end
  end

  describe "async projection enqueueing under an outer transaction" do
    let(:event) { Examples::DepositEvents::Created.new(value: 42, effective_date: Date.today) }

    it "does not enqueue async projections when the outer transaction rolls back after append!" do
      assert_no_enqueued_jobs do
        assert_raises(RuntimeError) do
          ActiveRecord::Base.transaction do
            EventStreamWithAsync.for(idx).append!(event)
            raise "rollback the outer transaction"
          end
        end
      end
    end

    it "enqueues async projections when the outer transaction commits" do
      assert_enqueued_with(job: Funes::PersistProjectionJob) do
        ActiveRecord::Base.transaction do
          EventStreamWithAsync.for(idx).append!(event)
        end
      end
    end
  end
end
