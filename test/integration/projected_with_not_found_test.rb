require "test_helper"

class ProjectedWithNotFoundTest < ActionDispatch::IntegrationTest
  test "returns 404 when the event stream has no events to project" do
    get "/examples/deposit_snapshots/does-not-exist"

    assert_equal 404, response.status
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
