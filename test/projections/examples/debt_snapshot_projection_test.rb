require "test_helper"
require "minitest/spec"

module Examples
  class DebtSnapshotProjectionTest < ActiveSupport::TestCase
    extend Minitest::Spec::DSL
    include Funes::ProjectionTestHelper

    describe "events handling" do
      describe "debt issued" do
        it "sets the initial outstanding balance and issuance date" do
          assert_equal interpret_event_based_on(Examples::DebtSnapshotProjection,
                                                Examples::Debt::Issued.new(value: 100, at: Date.new(2023, 5, 10)),
                                                Examples::DebtVirtualSnapshot.new),
                       { issued_value: 100,
                         outstanding_balance: 100,
                         issued_at: Date.new(2023, 5, 10),
                         last_payment_at: nil }
        end
      end
    end

    describe "overall interpretations" do
      events = [ Examples::Debt::Issued.new(value: 100, at: Date.new(2025, 1, 1)),
                 Examples::Debt::Paid.new(value: 50, discount: 0, at: Date.new(2025, 2, 15)),
                 Examples::Debt::AdjustedByIndex.new(rate: 0.03, index: "xpto", at: Date.new(2025, 3, 1)),
                 Examples::Debt::Paid.new(value: 50, discount: 1.5, at: Date.new(2025, 3, 15)) ]

      it "processes all events and results in zero balance after the last payment" do
        assert_equal({ issued_value: 100,
                       outstanding_balance: 0,
                       issued_at: Date.new(2025, 1, 1),
                       last_payment_at: Date.new(2025, 3, 15) },
                     Examples::DebtSnapshotProjection.process_events(events).attributes.transform_keys(&:to_sym))
      end
    end
  end
end
