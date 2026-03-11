require "test_helper"
require "minitest/spec"

module Examples
  class DepositEventStreamTest < ActiveSupport::TestCase
    extend Minitest::Spec::DSL
    include Funes::ProjectionTestHelper

    stream_idx = "deposit_123"

    describe "default state" do
      it "does not have events for the expected stream" do
        assert_empty DepositEventStream.for(stream_idx).events
      end

      it "does not have a snapshot" do
        assert_raises(ActiveRecord::RecordNotFound) { Examples::Deposit::Snapshot.find(stream_idx) }
      end
    end

    describe "deposit creation" do
      describe "with an invalid creation event" do
        let(:creation_event) { DepositEvents::Created.new(effective_date: Time.current, value: -5_000) }

        before do
          DepositEventStream.for(stream_idx).append(creation_event)
        end

        it "does not persist the event" do
          refute creation_event.persisted?
        end

        it "reports own errors on the event" do
          assert_equal [ "must be greater than 0" ], creation_event.own_errors[:value]
          assert_empty creation_event.state_errors
        end

        it "does not create a snapshot" do
          assert_raises(ActiveRecord::RecordNotFound) { Examples::Deposit::Snapshot.find(stream_idx) }
        end
      end

      describe "with a valid creation event" do
        let(:creation_event) { DepositEvents::Created.new(effective_date: Time.current, value: 5_000) }

        before do
          DepositEventStream.for(stream_idx).append(creation_event)
        end

        it "persists the new event" do
          assert creation_event.persisted?
        end

        it "has no errors" do
          assert creation_event.errors.empty?
        end

        it "creates a snapshot with the deposit values" do
          snapshot = Examples::Deposit::Snapshot.find(stream_idx)
          assert_not_nil snapshot
          assert_equal 5_000, snapshot.original_value
          assert_equal 5_000, snapshot.balance
          assert snapshot.active?
        end
      end
    end

    describe "deposit withdrawn" do
      let(:original_deposit_value) { 5_000 }

      before do
        DepositEventStream
          .for(stream_idx)
          .append(DepositEvents::Created.new(effective_date: Time.current, value: original_deposit_value))
      end

      describe "with an invalid withdrawn event" do
        let(:withdrawn_event) { DepositEvents::Withdrawn.new(amount: -1_000, effective_date: Time.current) }

        before { DepositEventStream.for(stream_idx).append(withdrawn_event) }

        it "does not persist the new event" do
          refute withdrawn_event.persisted?
        end

        it "reports own errors on the event" do
          assert_equal [ "must be greater than 0" ], withdrawn_event.own_errors[:amount]
          assert_empty withdrawn_event.state_errors
        end

        it "does not update the snapshot" do
          assert_equal original_deposit_value, Examples::Deposit::Snapshot.find(stream_idx).balance
        end
      end

      describe "with a valid withdrawn event that leads to an invalid state" do
        let(:withdrawn_event) { DepositEvents::Withdrawn.new(amount: 7_000, effective_date: Time.current) }

        before { DepositEventStream.for(stream_idx).append(withdrawn_event) }

        it "does not persist the new event" do
          refute withdrawn_event.persisted?
        end

        it "reports state errors on the event" do
          assert_empty withdrawn_event.own_errors
          assert_equal [ "must be greater than or equal to 0" ], withdrawn_event.state_errors[:balance]
        end

        it "does not update the snapshot" do
          assert_equal original_deposit_value, Examples::Deposit::Snapshot.find(stream_idx).balance
          assert Examples::Deposit::Snapshot.find(stream_idx).active?
        end
      end

      describe "with a valid withdrawn event that leads to a valid state" do
        let(:withdrawn_event) { DepositEvents::Withdrawn.new(amount: 3_000, effective_date: Time.current) }

        before { DepositEventStream.for(stream_idx).append(withdrawn_event) }

        it "persists the new event" do
          assert withdrawn_event.persisted?
        end

        it "has no errors" do
          assert_empty withdrawn_event.errors
        end

        it "updates the snapshot balance" do
          assert_equal 2_000, Examples::Deposit::Snapshot.find(stream_idx).balance
        end
      end
    end
  end
end
