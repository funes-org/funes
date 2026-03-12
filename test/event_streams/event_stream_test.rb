require "test_helper"
require "minitest/spec"

class EventStreamTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  let(:events) { [ Examples::DepositEvents::Created.new(value: 5_000, effective_date: Date.current),
                   Examples::DepositEvents::Withdrawn.new(amount: 3_000, effective_date: Date.current) ] }

  describe "append method" do
    describe "the happy path" do
      describe "with a fresh event stream" do
        event_stream_id = "hadouken"

        it "persists the event to the event log" do
          assert_difference -> { Funes::EventEntry.count }, 1 do
            Examples::DepositEventStream.for(event_stream_id).append events.first
          end
        end

        it "adds the transactional projection to the database" do
          assert_difference -> { Examples::Deposit::Snapshot.count }, 1 do
            Examples::DepositEventStream.for(event_stream_id).append events.first
          end

          assert_equal 5_000, Examples::Deposit::Snapshot.find(event_stream_id).balance
        end
      end

      describe "with a previously created event stream" do
        event_stream_id = "hadouken"

        before do
          Examples::DepositEventStream.for(event_stream_id).append events.first
        end

        it "persists the event to the event log" do
          assert_difference -> { Funes::EventEntry.count }, 1 do
            Examples::DepositEventStream.for(event_stream_id).append events.second
          end
        end

        it "updates the existent stream's transactional projection record" do
          assert_no_difference -> { Examples::Deposit::Snapshot.count } do
            Examples::DepositEventStream.for(event_stream_id).append events.second
          end

          assert_equal 2_000, Examples::Deposit::Snapshot.find(event_stream_id).balance
        end
      end
    end
  end

  test "#to_param delegates to idx" do
    assert_equal "some-id", Examples::DepositEventStream.for("some-id").to_param
  end
end
