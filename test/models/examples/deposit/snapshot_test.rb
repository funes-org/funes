require "test_helper"
require "minitest/spec"

module Examples::Deposit
  class SnapshotTest < ActiveSupport::TestCase
    extend Minitest::Spec::DSL

    describe "status" do
      it "is active when status is active" do
        assert Snapshot.new(status: :active).active?
      end

      it "is withdrawn when status is withdrawn" do
        assert Snapshot.new(status: :withdrawn).withdrawn?
      end
    end
  end
end
