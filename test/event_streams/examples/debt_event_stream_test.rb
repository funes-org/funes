require "test_helper"
require "minitest/spec"

module Examples
  class DebtEventStreamTest < ActiveSupport::TestCase
    extend Minitest::Spec::DSL
    include Funes::ProjectionTestHelper

    describe "append!" do
      it "does not affect the database when some event (the second) led the system to an invalid state" do
        events = [ Examples::Debt::Issued.new(value: 100, at: Date.new(2025, 1, 1)),
                   Examples::Debt::Paid.new(value: 80, discount: 30, at: Date.new(2025, 2, 15)) ]

        assert_difference -> { Funes::EventEntry.count }, 1 do
          Examples::DebtEventStream.with_id("hadouken").append! events.first
        end

        assert_no_difference -> { Funes::EventEntry.count } do
          Examples::DebtEventStream.with_id("hadouken").append! events.second
        end

        assert_not_empty events.second.errors.map(&:type)
      end

      it "does not addect the database when the event is not valid" do
        wrong_event = Examples::Debt::Issued.new(value: -100, at: Date.today)

        assert_no_difference -> { Funes::EventEntry.count } do
          Examples::DebtEventStream.with_id("hadouken").append! wrong_event
        end

        assert_not_empty wrong_event.errors.map(&:type)
      end
    end

    describe "expeculative_append" do
      it "foo" do
        stream = Examples::DebtEventStream.with_id("hadouken")
        stream.append! Examples::Debt::Issued.new(value: 100, at: Date.new(2025, 1, 1))
        snapshot = stream.expeculative_append(Examples::Debt::Paid.new(value: 30, discount: 20, at: Date.new(2025, 2, 15)),
                                              Examples::DebtSnapshotProjection)

        assert snapshot.valid?
        assert_equal snapshot.outstanding_balance, 50
      end
    end
  end
end
