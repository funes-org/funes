require "test_helper"
require "minitest/spec"
require "json"
require "fileutils"

module Examples::Deposit
  class JsonSnapshotProjectionTest < ActiveSupport::TestCase
    extend Minitest::Spec::DSL

    let(:today) { Date.today }
    let(:idx) { "deposit-json-#{SecureRandom.hex(4)}" }
    let(:storage_path) { Examples::Deposit::JsonSnapshot.storage_path_for(idx) }

    before do
      FileUtils.mkdir_p(File.dirname(storage_path))
      FileUtils.rm_f(storage_path)
    end

    after do
      FileUtils.rm_f(storage_path)
    end

    describe "single Created event" do
      it "writes a JSON file with the materialized snapshot" do
        Examples::Deposit::JsonSnapshotProjection.materialize!(
          [ Examples::DepositEvents::Created.new(value: 100, effective_date: today) ], idx, at: today)

        assert File.exist?(storage_path)
        payload = JSON.parse(File.read(storage_path))
        assert_equal idx, payload["idx"]
        assert_equal "100.0", payload["original_value"]
        assert_equal "100.0", payload["balance"]
        assert_equal "active", payload["status"]
      end
    end

    describe "Created followed by Withdrawn events" do
      it "reflects the running balance and status in the file" do
        events = [
          Examples::DepositEvents::Created.new(value: 100, effective_date: today),
          Examples::DepositEvents::Withdrawn.new(amount: 30, effective_date: today),
          Examples::DepositEvents::Withdrawn.new(amount: 70, effective_date: today)
        ]

        Examples::Deposit::JsonSnapshotProjection.materialize!(events, idx, at: today)

        payload = JSON.parse(File.read(storage_path))
        assert_equal "0.0", payload["balance"]
        assert_equal "withdrawn", payload["status"]
      end
    end

    describe "re-running materialize! with the same events" do
      it "overwrites the existing file rather than appending" do
        events = [ Examples::DepositEvents::Created.new(value: 100, effective_date: today) ]

        Examples::Deposit::JsonSnapshotProjection.materialize!(events, idx, at: today)
        first_size = File.size(storage_path)
        Examples::Deposit::JsonSnapshotProjection.materialize!(events, idx, at: today)
        second_size = File.size(storage_path)

        assert_equal first_size, second_size
      end
    end

    describe "when the resulting state is invalid" do
      it "raises ActiveRecord::RecordInvalid and does not write the file" do
        events = [
          Examples::DepositEvents::Created.new(value: 100, effective_date: today),
          Examples::DepositEvents::Withdrawn.new(amount: 150, effective_date: today)
        ]

        assert_raises ActiveRecord::RecordInvalid do
          Examples::Deposit::JsonSnapshotProjection.materialize!(events, idx, at: today)
        end
        refute File.exist?(storage_path)
      end
    end
  end
end
