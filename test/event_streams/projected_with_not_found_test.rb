require "test_helper"
require "minitest/spec"

class EventStreamProjectedWithNotFoundTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  describe "Funes::EventStream#projected_with when there are no events to project" do
    it "raises ActiveRecord::RecordNotFound when the stream has no events at all" do
      idx = "deposit-empty-stream-#{SecureRandom.uuid}"

      assert_raises ActiveRecord::RecordNotFound do
        Examples::DepositEventStream.for(idx).projected_with(Examples::Deposit::SnapshotProjection)
      end
    end

    it "raises ActiveRecord::RecordNotFound when at: filters out every event" do
      idx = "deposit-at-excludes-all-#{SecureRandom.uuid}"
      Examples::DepositEventStream
        .for(idx)
        .append(Examples::DepositEvents::Created.new(effective_date: Time.new(2025, 4, 1), value: 5_000))

      assert_raises ActiveRecord::RecordNotFound do
        Examples::DepositEventStream
          .for(idx)
          .projected_with(Examples::Deposit::SnapshotProjection, at: Time.new(2025, 1, 1))
      end
    end

    it "raises ActiveRecord::RecordNotFound when as_of: filters out every event" do
      idx = "deposit-as-of-excludes-all-#{SecureRandom.uuid}"

      travel_to Time.new(2025, 4, 1, 12, 0, 0) do
        Examples::DepositEventStream
          .for(idx)
          .append(Examples::DepositEvents::Created.new(effective_date: Time.new(2025, 4, 1), value: 5_000))
      end

      assert_raises ActiveRecord::RecordNotFound do
        Examples::DepositEventStream
          .for(idx)
          .projected_with(Examples::Deposit::SnapshotProjection, as_of: Time.new(2025, 1, 1))
      end
    end

    it "exposes idx on the raised error so logs and trackers see the identifier" do
      idx = "deposit-error-attrs-#{SecureRandom.uuid}"

      error = assert_raises ActiveRecord::RecordNotFound do
        Examples::DepositEventStream.for(idx).projected_with(Examples::Deposit::SnapshotProjection)
      end

      assert_equal "idx", error.primary_key
      assert_equal idx, error.id
      assert_includes error.message, idx
    end

    it "logs an info line with stream, idx, projection, and filter context before raising" do
      idx = "deposit-log-#{SecureRandom.uuid}"
      io = StringIO.new
      original_logger = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(io)
      at = Time.new(2025, 1, 1)

      begin
        assert_raises ActiveRecord::RecordNotFound do
          Examples::DepositEventStream
            .for(idx)
            .projected_with(Examples::Deposit::SnapshotProjection, at:)
        end
      ensure
        Rails.logger = original_logger
      end

      log_output = io.string
      assert_includes log_output, "[Funes] projected_with found no events"
      assert_includes log_output, "idx=#{idx.inspect}"
      assert_includes log_output, "at=#{at.inspect}"
      assert_includes log_output, "as_of=nil"
    end
  end
end
