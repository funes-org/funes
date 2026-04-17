require "test_helper"

class AsyncProjectionsIntegrationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  class EventStreamWithAsyncSnapshot < Funes::EventStream
    add_async_projection Examples::Deposit::SnapshotProjection
  end

  test "async projection materializes after perform_enqueued_jobs" do
    EventStreamWithAsyncSnapshot
      .for("order-e2e-1")
      .append(Examples::DepositEvents::Created.new(value: 150, effective_date: Date.today))

    perform_enqueued_jobs

    assert Examples::Deposit::Snapshot.exists?("order-e2e-1")
    assert_equal 150, Examples::Deposit::Snapshot.find("order-e2e-1").balance
  end

  test "async projection materializes after a JSON round-trip of the enqueued job (simulating a real queue backend)" do
    EventStreamWithAsyncSnapshot
      .for("order-e2e-2")
      .append(Examples::DepositEvents::Created.new(value: 200, effective_date: Date.today))

    enqueued_job = ActiveJob::Base.queue_adapter.enqueued_jobs.first
    over_the_wire = JSON.parse(JSON.dump(enqueued_job))

    ActiveJob::Base.execute(over_the_wire)

    assert Examples::Deposit::Snapshot.exists?("order-e2e-2")
    assert_equal 200, Examples::Deposit::Snapshot.find("order-e2e-2").balance
  end
end
