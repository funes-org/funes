require "test_helper"

class ProjectedWithNotFoundTest < ActionDispatch::IntegrationTest
  setup do
    @log_output = StringIO.new
    @original_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(@log_output)
  end

  teardown do
    Rails.logger = @original_logger
  end

  test "returns 404 and logs the [Funes] info line when the stream has no events to project" do
    idx = "deposit-404-#{SecureRandom.uuid}"

    get "/examples/deposit_snapshots/#{idx}"

    assert_equal 404, response.status
    assert_includes @log_output.string, "[Funes] projected_with found no events"
    assert_includes @log_output.string, "Examples::DepositEventStream"
    assert_includes @log_output.string, "idx=#{idx.inspect}"
    assert_includes @log_output.string, "projection=Examples::Deposit::SnapshotProjection"
    assert_includes @log_output.string, "as_of=nil"
    assert_includes @log_output.string, "at=nil"
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

  test "returns 404 and logs the at: filter when the stream's events are excluded by at:" do
    idx = "deposit-at-excludes-#{SecureRandom.uuid}"
    at = Time.new(2025, 1, 1)
    Examples::DepositEventStream
      .for(idx)
      .append(Examples::DepositEvents::Created.new(effective_date: Time.new(2025, 4, 1), value: 5_000))

    get "/examples/deposit_snapshots/#{idx}", params: { at: at.iso8601 }

    assert_equal 404, response.status
    assert_includes @log_output.string, "[Funes] projected_with found no events"
    assert_includes @log_output.string, "idx=#{idx.inspect}"
    assert_includes @log_output.string, "at=#{at.inspect}"
    assert_includes @log_output.string, "as_of=nil"
  end

  test "returns 404 and logs the as_of: filter when the stream's events are excluded by as_of:" do
    idx = "deposit-as-of-excludes-#{SecureRandom.uuid}"
    as_of = Time.new(2025, 1, 1)
    travel_to Time.new(2025, 4, 1, 12, 0, 0) do
      Examples::DepositEventStream
        .for(idx)
        .append(Examples::DepositEvents::Created.new(effective_date: Time.new(2025, 4, 1), value: 5_000))
    end

    get "/examples/deposit_snapshots/#{idx}", params: { as_of: as_of.iso8601 }

    assert_equal 404, response.status
    assert_includes @log_output.string, "[Funes] projected_with found no events"
    assert_includes @log_output.string, "idx=#{idx.inspect}"
    assert_includes @log_output.string, "as_of=#{as_of.inspect}"
    assert_includes @log_output.string, "at=nil"
  end
end
