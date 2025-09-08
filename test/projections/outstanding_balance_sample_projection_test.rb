require "test_helper"
require "minitest/spec"

class OutstandingBalanceSampleProjectionTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL
  include Funes::ProjectionTestHelper

  describe "events handling" do
    describe "debt issued" do
      it "sets the event value as initial outstanding balance" do
        assert_equal 10, apply_event_to_state(OutstandingBalanceSampleProjection, nil,
                                              { type: "Debt::Issued", value: 10 })
      end
    end

    describe "debt paid" do
      it "reduces the outstanding balance by payment value and discount amount (sum of both)" do
        assert_equal 10, apply_event_to_state(OutstandingBalanceSampleProjection, 20,
                                              { type: "Debt::Paid", value: 5, discount: 5 })
      end

      it "raises an error when payment processing would result in negative balance" do
        assert_raise Funes::LedToInvalidState, "The outstanding balance can't be negative" do
          apply_event_to_state(OutstandingBalanceSampleProjection, 5,
                               { type: "Debt::Paid", value: 5, discount: 5 })
        end
      end
    end

    describe "debt adjusted by index" do
      it "increases outstanding balance by the specified positive rate" do
        assert_equal 110, apply_event_to_state(OutstandingBalanceSampleProjection, 100,
                                               { type: "Debt::AdjustedByIndex", rate: 0.1 })
      end

      it "decreases outstanding balance when applying negative rate" do
        assert_equal 90, apply_event_to_state(OutstandingBalanceSampleProjection, 100,
                                              { type: "Debt::AdjustedByIndex", rate: -0.1 })
      end

      it "keeps outstanding balance unchanged when rate is zero" do
        assert_equal 100, apply_event_to_state(OutstandingBalanceSampleProjection, 100,
                                               { type: "Debt::AdjustedByIndex", rate: 0 })
      end
    end
  end

  describe "the handling for an entire debt events stream" do
    events = [ { type: "Debt::Issued",
                 value: 100,
                 at: Date.new(2025, 1, 1) },
               { type: "Debt::Paid",
                 value: 50,
                 discount: 0,
                 at: Date.new(2025, 2, 15) },
               { type: "Debt::AdjustedByIndex",
                 rate: 0.03,
                 index: :xpto,
                 at: Date.new(2025, 3, 1) },
               { type: "Debt::Paid",
                 value: 50,
                 discount: 1.5,
                 at: Date.new(2025, 3, 15) } ]

    it "processes all events and results in zero balance after the last payment" do
      assert_equal 0, OutstandingBalanceSampleProjection.process_events(events)
    end

    it "processes partially the events and infers the proper outstanding balance before the last payment" do
      assert_equal 51.5, OutstandingBalanceSampleProjection.process_events(events.take(3))
    end
  end
end
