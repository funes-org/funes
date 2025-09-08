require "test_helper"
require "minitest/spec"

class OutstandingBalanceSampleProjectionTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL
  include Funes::ProjectionTestHelper

  describe "events handling" do
    describe "debt issued" do
      it "sets the event value as initial outstanding balance" do
        assert_equal 10, project_event_based_on(OutstandingBalanceSampleProjection, Debt::Issued.new(value: 10), nil)
      end
    end

    describe "debt paid" do
      it "reduces the outstanding balance by payment value and discount amount (sum of both)" do
        assert_equal 10, project_event_based_on(OutstandingBalanceSampleProjection,
                                                Debt::Paid.new(value: 5, discount: 5), 20)
      end

      it "raises an error when payment processing would result in negative balance" do
        assert_raise Funes::LedToInvalidState, "The outstanding balance can't be negative" do
          project_event_based_on(OutstandingBalanceSampleProjection, Debt::Paid.new(value: 5, discount: 5), 5)
        end
      end
    end

    describe "debt adjusted by index" do
      it "increases outstanding balance by the specified positive rate" do
        assert_equal 110, project_event_based_on(OutstandingBalanceSampleProjection,
                                                 Debt::AdjustedByIndex.new(rate: 0.1), 100)
      end

      it "decreases outstanding balance when applying negative rate" do
        assert_equal 90, project_event_based_on(OutstandingBalanceSampleProjection,
                                                Debt::AdjustedByIndex.new(rate: -0.1), 100)
      end

      it "keeps outstanding balance unchanged when rate is zero" do
        assert_equal 100, project_event_based_on(OutstandingBalanceSampleProjection,
                                                 Debt::AdjustedByIndex.new(rate: 0), 100)
      end
    end
  end

  describe "the handling for an entire debt events stream" do
    events = [ Debt::Issued.new(value: 100, at: Date.new(2025, 1, 1)),
               Debt::Paid.new(value: 50, discount: 0, at: Date.new(2025, 2, 15)),
               Debt::AdjustedByIndex.new(rate: 0.03, index: "xpto", at: Date.new(2025, 3, 1)),
               Debt::Paid.new(value: 50, discount: 1.5, at: Date.new(2025, 3, 15)) ]

    it "processes all events and results in zero balance after the last payment" do
      assert_equal 0, OutstandingBalanceSampleProjection.process_events(events)
    end

    it "processes partially the events and infers the proper outstanding balance before the last payment" do
      assert_equal 51.5, OutstandingBalanceSampleProjection.process_events(events.take(3))
    end
  end
end
