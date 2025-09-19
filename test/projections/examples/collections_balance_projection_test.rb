require "test_helper"
require "minitest/spec"

class Examples::CollectionsBalanceProjectionTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL
  include Funes::ProjectionTestHelper

  describe "events handling" do
    describe "debt issued" do
      it "sets the initial outstanding balance and issuance date" do
        event = Debt::Issued.new(value: 100, at: Date.new(2023, 5, 10))

        assert_equal interpret_event_based_on(Examples::CollectionsBalanceProjection, event, nil),
                     { outstanding_balance: 100,
                       issuance_date: Date.new(2023, 5, 10),
                       last_payment_date: nil }
      end
    end

    describe "debt paid" do
      initial_state = { outstanding_balance: 100, issuance_date: Date.new(2023, 5, 10), last_payment_date: nil }

      it "reduces the outstanding balance and updates last payment date" do
        event = Debt::Paid.new(value: 30, discount: 5, at: Date.new(2023, 6, 15))

        assert_equal interpret_event_based_on(Examples::CollectionsBalanceProjection, event, initial_state),
                     { outstanding_balance: 65,
                       issuance_date: Date.new(2023, 5, 10),
                       last_payment_date: Date.new(2023, 6, 15) }
      end

      it "raises an error when payment would result in negative balance" do
        event = Debt::Paid.new(value: 100, discount: 10, at: Date.new(2023, 6, 15))

        assert_raise Funes::LedToInvalidState do
          interpret_event_based_on(Examples::CollectionsBalanceProjection, event, initial_state)
        end
      end
    end

    describe "debt adjusted by index" do
      it "increases the outstanding balance by the specified rate" do
        initial_state = { outstanding_balance: 100, issuance_date: Date.new(2023, 5, 10), last_payment_date: nil }
        event = Debt::AdjustedByIndex.new(rate: 0.1, index: "test", at: Date.new(2023, 7, 1))

        assert_equal interpret_event_based_on(Examples::CollectionsBalanceProjection, event, initial_state),
                     { outstanding_balance: 110,
                       issuance_date: Date.new(2023, 5, 10),
                       last_payment_date: nil }
      end
    end
  end

  events_log = [ Debt::Issued.new(value: 100, at: Date.new(2025, 1, 1)),
                 Debt::Paid.new(value: 50, discount: 0, at: Date.new(2025, 2, 15)),
                 Debt::AdjustedByIndex.new(rate: 0.03, index: "xpto", at: Date.new(2025, 3, 1)),
                 Debt::Paid.new(value: 50, discount: 1.5, at: Date.new(2025, 3, 15)) ]


  describe "the handling for an entire debt events log" do
    it "correctly processes the full sequence leading to zero balance" do
      assert_equal({ outstanding_balance: 0.0,
                     issuance_date: Date.new(2025, 1, 1),
                     last_payment_date: Date.new(2025, 3, 15) },
                   Examples::CollectionsBalanceProjection.process_events(events_log))
    end

    it "correctly processes partial sequence with outstanding balance" do
      assert_equal({ outstanding_balance: 51.5,
                     issuance_date: Date.new(2025, 1, 1),
                     last_payment_date: Date.new(2025, 2, 15) },
                   Examples::CollectionsBalanceProjection.process_events(events_log.take(3)))
    end
  end

  describe "the persistence of the materialization model" do
    it "creates a new materialization record with correct attributes" do
      assert_difference -> { DebtCollectionsProjection.count }, 1 do
        Examples::CollectionsBalanceProjection.materialize!(events_log.take(3), "some-id")
      end

      record = DebtCollectionsProjection.find_by(idx: "some-id")
      expected_attributes = Examples::CollectionsBalanceProjection.process_events(events_log.take(3))

      assert_equal(expected_attributes, record.attributes.symbolize_keys.slice(*expected_attributes.keys))
    end

    it "updates existing materialization record without creating a new one - with correct attributes" do
      Examples::CollectionsBalanceProjection.materialize!(events_log.take(3), "some-id")

      assert_no_difference -> { DebtCollectionsProjection.count } do
        Examples::CollectionsBalanceProjection.materialize!(events_log, "some-id")
      end

      record = DebtCollectionsProjection.find_by(idx: "some-id")
      expected_attributes = Examples::CollectionsBalanceProjection.process_events(events_log)

      assert_equal(expected_attributes, record.attributes.symbolize_keys.slice(*expected_attributes.keys))
    end
  end
end
