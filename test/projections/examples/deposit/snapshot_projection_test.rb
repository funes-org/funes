require "test_helper"
require "minitest/spec"

module Examples::Deposit
  class SnapshotProjectionTest < ActiveSupport::TestCase
    extend Minitest::Spec::DSL
    include Funes::ProjectionTestHelper

    describe "DepositEvents::Created" do
      it "sets original_value and balance from the event value" do
        interpretation = interpret_event_based_on(Examples::Deposit::SnapshotProjection,
                                                  Examples::DepositEvents::Created.new(effective_date: Time.current,
                                                                                       value: 10_000),
                                                  Examples::Deposit::Snapshot.new)

        assert_equal 10_000, interpretation.original_value
        assert_equal 10_000, interpretation.balance
      end

      it "sets status to active" do
        assert interpret_event_based_on(Examples::Deposit::SnapshotProjection,
                                        Examples::DepositEvents::Created.new(effective_date: Time.current,
                                                                             value: 10_000),
                                        Examples::Deposit::Snapshot.new).active?
      end

      it "sets created_at from the event time" do
        event_time = Time.current

        assert_equal event_time.to_date,
                     interpret_event_based_on(Examples::Deposit::SnapshotProjection,
                                              Examples::DepositEvents::Created.new(effective_date: event_time,
                                                                                   value: 10_000),
                                              Examples::Deposit::Snapshot.new,
                                              event_time).created_at
      end
    end

    describe "DepositEvents::Withdrawn" do
      it "subtracts the withdrawn amount from the balance" do
        assert_equal 7_000,
                     interpret_event_based_on(Examples::Deposit::SnapshotProjection,
                                              Examples::DepositEvents::Withdrawn.new(effective_date: Time.current,
                                                                                     amount: 3_000),
                                              Examples::Deposit::Snapshot.new(balance: 10_000, status: :active)).balance
      end

      it "keeps status active when balance remains positive" do
        assert interpret_event_based_on(Examples::Deposit::SnapshotProjection,
                                        Examples::DepositEvents::Withdrawn.new(effective_date: Time.current,
                                                                               amount: 3_000),
                                        Examples::Deposit::Snapshot.new(balance: 10_000, status: :active)).active?
      end

      it "sets status to withdrawn when balance reaches zero" do
        assert interpret_event_based_on(Examples::Deposit::SnapshotProjection,
                                        Examples::DepositEvents::Withdrawn.new(effective_date: Time.current,
                                                                               amount: 10_000),
                                        Examples::Deposit::Snapshot.new(balance: 10_000, status: :active)).withdrawn?
      end
    end
  end
end
