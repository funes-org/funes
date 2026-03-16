require "test_helper"
require "minitest/spec"

class TransactionalControlForNewEventsTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  class FailingProjection < Funes::Projection
    materialization_model Examples::Deposit::Snapshot

    interpretation_for Examples::DepositEvents::Created do |state, _event, _as_of|
      state.assign_attributes(balance: nil) # violates a NOT NULL constraint
      state
    end
  end

  let(:idx) { "some-random-#{SecureRandom.uuid}" }

  describe "when event insertion and transactional projections succeed" do
    let(:event) { Examples::DepositEvents::Created.new(value: 42, effective_date: Date.today) }

    before { Examples::DepositEventStream.for(idx).append(event) }

    it "persists the event" do
      assert event.persisted?
      assert_equal 1, Funes::EventEntry.where(idx: idx, klass: "Examples::DepositEvents::Created").count
    end

    it "persists the materialization of the transactional projections" do
      assert Examples::Deposit::Snapshot.exists?(idx)
      assert Examples::Deposit::LastActivities.exists?(idx)
    end
  end

  describe "when EventEntry insertion fails due to version conflict" do
    let(:event) { Examples::DepositEvents::Created.new(value: 42, effective_date: Date.today) }

    before do
      Funes::EventEntry.create!(klass: Examples::DepositEvents::Created.name, idx: idx, version: 1,
                                props: { value: 100, effective_date: Date.today }, occurred_at: Time.current)

      Examples::DepositEventStream.for(idx).append(event)
    end

    it "does not create the transactional projection materialization" do
      assert_equal 0, Examples::Deposit::Snapshot.where(idx: idx).count
    end

    it "does not mark the event as persisted" do
      assert_not event.persisted?
    end

    it "adds the racing condition error to the event's errors" do
      assert event.errors[:base].present?
    end

    it "does not create a materialization for this idx" do
      refute Examples::Deposit::Snapshot.exists?(idx: idx)
    end
  end

  describe "when the consistency projection fails" do
    let(:withdraw_event_exceeding_deposit_balance) { Examples::DepositEvents::Withdrawn
                                                 .new(amount: 80, effective_date: Date.today) }

    before do
      Examples::DepositEventStream
        .for(idx)
        .append(Examples::DepositEvents::Created.new(value: 42, effective_date: Date.today))
    end

    it "does not persist the event that could lead to inconsistency" do
      assert_no_difference -> { Funes::EventEntry.count } do
        Examples::DepositEventStream.for(idx).append(withdraw_event_exceeding_deposit_balance)
      end
      refute withdraw_event_exceeding_deposit_balance.persisted?
    end

    it "does not touch the previously persisted materializations" do
      previous_snapshot = Examples::Deposit::Snapshot.find(idx)
      previous_last_activities = Examples::Deposit::LastActivities.find(idx)
      Examples::DepositEventStream.for(idx).append(withdraw_event_exceeding_deposit_balance)

      assert_equal previous_snapshot.attributes, Examples::Deposit::Snapshot.find(idx).attributes
      assert_equal previous_last_activities.attributes, Examples::Deposit::LastActivities.find(idx).attributes
    end
  end

  describe "when the single transactional projection fails on upsert" do
    let(:event) { Examples::DepositEvents::Created.new(value: 42, effective_date: Date.today) }

    before do
      assert_raises(ActiveRecord::NotNullViolation) do
        SpecFailingExamples::SingleTransactionalProjection::DepositEventStream.for(idx).append(event)
      end
    end

    it "raises the original database exception and doesn't persist the event in the event log" do
      refute Funes::EventEntry.exists?(idx: idx)
      refute event.persisted?
    end

    it "doesn't persist the projection materialization model" do
      refute Examples::Deposit::LastActivities.exists?(idx: idx)
    end
  end

  describe "when the single transactional projection fails on AR validation" do
    it { skip :pending }
  end

  describe "when one of multiple transactional projections fails on upsert" do
    let(:event) { Examples::DepositEvents::Created.new(value: 42, effective_date: Date.today) }

    before do
      assert_raises(ActiveRecord::NotNullViolation) do
        SpecFailingExamples::TwoTransactionalProjections::DepositEventStream.for(idx).append(event)
      end
    end

    it "raises the original database exception and doesn't persist the event in the event log" do
      refute Funes::EventEntry.exists?(idx: idx)
      refute event.persisted?
    end

    it "doesn't persist the projection materialization model" do
      refute Examples::Deposit::LastActivities.exists?(idx: idx)
    end

    it "raises the original database error and rolls back all changes (all-or-nothing)" do
      skip :drop
      idx = "txn-multi-proj-fail-#{SecureRandom.uuid}"
      event = Examples::DepositEvents::Created.new(value: 42, effective_date: Date.today)

      assert_raises(ActiveRecord::StatementInvalid) do
        StreamWithMultipleProjections.for(idx).append(event)
      end

      assert_not event.persisted?
      refute Funes::EventEntry.exists?(idx: idx)
      refute Examples::Deposit::Snapshot.exists?(idx: idx)
    end
  end

  describe "when one of multiple transactional projection fails on AR validation" do
    it { skip :pending }
  end
end
