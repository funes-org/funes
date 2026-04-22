require "test_helper"

class ProjectedWithNotFoundTest < ActionDispatch::IntegrationTest
  test "returns 404 and logs the [Funes] info line when the stream has no events to project" do
    idx = "deposit-404-#{SecureRandom.uuid}"
    io = StringIO.new
    original_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)

    begin
      get "/examples/deposit_snapshots/#{idx}"
    ensure
      Rails.logger = original_logger
    end

    assert_equal 404, response.status
    assert_includes io.string, "[Funes] projected_with found no events"
    assert_includes io.string, "Examples::DepositEventStream"
    assert_includes io.string, "idx=#{idx.inspect}"
    assert_includes io.string, "projection=Examples::Deposit::SnapshotProjection"
  end

  test "returns 200 when the event stream has events to project" do
    idx = "deposit-integration-#{SecureRandom.uuid}"
    Examples::DepositEventStream
      .for(idx)
      .append(Examples::DepositEvents::Created.new(effective_date: Time.current, value: 5_000))

    get "/examples/deposit_snapshots/#{idx}"

    assert_equal 200, response.status
    assert_match(/\Abalance=5000(\.0+)?\z/, response.body)
  end
end
