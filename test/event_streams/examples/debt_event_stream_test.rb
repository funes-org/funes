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
        assert_not_empty events.second.state_errors.map(&:type)
        assert_empty events.second.own_errors.map(&:type)
      end

      it "does not add the event to the database when it is not valid" do
        invalid_event = Examples::Debt::Issued.new(value: -100, at: Date.today)

        assert_no_difference -> { Funes::EventEntry.count } do
          Examples::DebtEventStream.with_id("hadouken").append! invalid_event
        end

        assert_not_empty invalid_event.errors.map(&:type)
        assert_empty invalid_event.state_errors.map(&:type)
        assert_not_empty invalid_event.own_errors.map(&:type)
      end

      it "handles properly the writing concurrency for 2 stream instances with the same stream state" do
        Examples::DebtEventStream.with_id("hadouken").append! Examples::Debt::Issued.new(value: 100, at: Date.new(2025, 1, 1))
        first_stream_instance = Examples::DebtEventStream.with_id("hadouken")
        second_stream_instance = Examples::DebtEventStream.with_id("hadouken")

        assert_difference -> { Funes::EventEntry.count }, 1 do
          first_stream_instance.append! Examples::Debt::Paid.new(value: 50, discount: 0, at: Date.new(2025, 2, 15))
        end

        assert_no_difference -> { Funes::EventEntry.count } do
          second_stream_instance.append! Examples::Debt::Paid.new(value: 50, discount: 0, at: Date.new(2025, 2, 15))
        end
      end
    end
  end
end
