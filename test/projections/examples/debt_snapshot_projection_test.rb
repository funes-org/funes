require "test_helper"
require "minitest/spec"

module Examples
  class DebtSnapshotProjectionTest < ActiveSupport::TestCase
    extend Minitest::Spec::DSL
    include Funes::ProjectionTestHelper

    describe "events handling" do
      describe "debt issued" do
        it "sets the initial outstanding balance and issuance date" do
          computed_model = interpret_event_based_on(Examples::DebtSnapshotProjection,
                                                    Examples::Debt::Issued.new(value: 100, at: Date.new(2023, 5, 10)),
                                                    Examples::DebtVirtualSnapshot.new)

          assert_instance_of Examples::DebtVirtualSnapshot, computed_model
          assert_equal computed_model.issued_value, 100
          assert_equal computed_model.outstanding_balance, 100
          assert_equal computed_model.issued_at, Date.new(2023, 5, 10)
          assert_nil   computed_model.last_payment_at
        end
      end

      describe "debt paid" do
        it "foo" do
          computed_model = interpret_event_based_on(Examples::DebtSnapshotProjection,
                                                    Examples::Debt::Paid.new(value: 25, discount: 10, at: Date.today),
                                                    Examples::DebtVirtualSnapshot.new(outstanding_balance: 100,
                                                                                      last_payment_at: nil))

          assert_instance_of Examples::DebtVirtualSnapshot, computed_model
          assert_equal computed_model.outstanding_balance, 65
          assert_equal computed_model.last_payment_at, Date.today
        end
      end

      describe "by index adjustment" do
        it "foo" do
          computed_model = interpret_event_based_on(Examples::DebtSnapshotProjection,
                                                    Examples::Debt::AdjustedByIndex.new(rate: 0.03, index: "xpto",
                                                                                        at: Date.new(2025, 3, 1)),
                                                    Examples::DebtVirtualSnapshot.new(outstanding_balance: 100))

          assert_instance_of Examples::DebtVirtualSnapshot, computed_model
          assert_equal computed_model.outstanding_balance, 103
        end
      end
    end

    describe "overall interpretations" do
      events = [ Examples::Debt::Issued.new(value: 100, at: Date.new(2025, 1, 1)),
                 Examples::Debt::Paid.new(value: 50, discount: 0, at: Date.new(2025, 2, 15)),
                 Examples::Debt::AdjustedByIndex.new(rate: 0.03, index: "xpto", at: Date.new(2025, 3, 1)),
                 Examples::Debt::Paid.new(value: 50, discount: 1.5, at: Date.new(2025, 3, 15)) ]

      it "processes all events and results in zero balance after the last payment" do
        computed_model = Examples::DebtSnapshotProjection.process_events(events)

        assert_instance_of Examples::DebtVirtualSnapshot, computed_model
        assert_equal computed_model.issued_value, 100
        assert_equal computed_model.outstanding_balance, 0
        assert_equal computed_model.issued_at, Date.new(2025, 1, 1)
        assert_equal computed_model.last_payment_at, Date.new(2025, 3, 15)
      end
    end
  end
end
