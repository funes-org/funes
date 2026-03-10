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
    end

    describe "deposit creation" do
      it "does not accept/persist invalid creation events" do
        creation_event = DepositEvents::Created.new(effective_date: Time.current, value: -5_000)
        DepositEventStream.for(stream_idx).append(creation_event)

        refute creation_event.persisted?
        assert_equal [ "must be greater than 0" ], creation_event.own_errors[:value]
        assert_empty creation_event.state_errors
      end

      it "accepts/persists valid creation events" do
        creation_event = DepositEvents::Created.new(effective_date: Time.current, value: 5_000)
        DepositEventStream.for(stream_idx).append(creation_event)

        assert creation_event.persisted?
        assert_not_empty DepositEventStream.for(stream_idx).events
      end
    end

    describe "deposit withdrawn" do
      before do
        DepositEventStream
          .for(stream_idx)
          .append(DepositEvents::Created.new(effective_date: Time.current, value: 5_000))
      end

      it "does not accept/persist invalid withdrawn events" do
        withdrawn_event = DepositEvents::Withdrawn.new(amount: -1_000, effective_date: Time.current)
        DepositEventStream.for(stream_idx).append(withdrawn_event)

        refute withdrawn_event.persisted?
        assert_equal [ "must be greater than 0" ], withdrawn_event.own_errors[:amount]
        assert_empty withdrawn_event.state_errors
      end

      it "does not accept/persist valid withdrawn events that leads to invalid states" do
        withdrawn_event = DepositEvents::Withdrawn.new(amount: 7_000, effective_date: Time.current)
        DepositEventStream.for(stream_idx).append(withdrawn_event)

        refute withdrawn_event.persisted?
        assert_empty withdrawn_event.own_errors
        assert_equal [ "must be greater than or equal to 0" ], withdrawn_event.state_errors[:balance]
      end

      it "accepts/persists valid withdrawn events that leads to valid states" do
        withdrawn_event = DepositEvents::Withdrawn.new(amount: 3_000, effective_date: Time.current)
        DepositEventStream.for(stream_idx).append(withdrawn_event)

        assert withdrawn_event.persisted?
      end
    end
  end
end
