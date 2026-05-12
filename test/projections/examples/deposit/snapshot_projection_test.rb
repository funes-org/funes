require "test_helper"
require "minitest/spec"

module Examples::Deposit
  class SnapshotProjectionTest < ActiveSupport::TestCase
    extend Minitest::Spec::DSL
    include Funes::ProjectionTestHelper

    projection Examples::Deposit::SnapshotProjection

    describe "DepositEvents::Created" do
      it "sets original_value and balance from the event value" do
        result = interpret(Examples::DepositEvents::Created.new(effective_date: Time.current, value: 10_000),
                           given: Examples::Deposit::Snapshot.new)

        assert_equal 10_000, result.original_value
        assert_equal 10_000, result.balance
      end

      it "sets status to active" do
        assert interpret(Examples::DepositEvents::Created.new(effective_date: Time.current, value: 10_000),
                         given: Examples::Deposit::Snapshot.new).active?
      end

      it "sets created_at from the event time" do
        event_time = Time.current

        result = interpret(Examples::DepositEvents::Created.new(effective_date: event_time, value: 10_000),
                           given: Examples::Deposit::Snapshot.new,
                           at: event_time)

        assert_equal event_time.to_date, result.created_at
      end
    end

    describe "DepositEvents::Withdrawn" do
      it "subtracts the withdrawn amount from the balance" do
        result = interpret(Examples::DepositEvents::Withdrawn.new(effective_date: Time.current, amount: 3_000),
                           given: Examples::Deposit::Snapshot.new(balance: 10_000, status: :active))

        assert_equal 7_000, result.balance
      end

      it "keeps status active when balance remains positive" do
        assert interpret(Examples::DepositEvents::Withdrawn.new(effective_date: Time.current, amount: 3_000),
                         given: Examples::Deposit::Snapshot.new(balance: 10_000, status: :active)).active?
      end

      it "sets status to withdrawn when balance reaches zero" do
        assert interpret(Examples::DepositEvents::Withdrawn.new(effective_date: Time.current, amount: 10_000),
                         given: Examples::Deposit::Snapshot.new(balance: 10_000, status: :active)).withdrawn?
      end
    end
  end
end
