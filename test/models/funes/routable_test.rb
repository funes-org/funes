require "test_helper"
require "minitest/spec"

class Funes::RoutableTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  class DummyModel
    include Funes::Routable

    attr_accessor :idx

    def initialize(idx:)
      @idx = idx
    end
  end

  describe "#to_param" do
    it "returns the idx value" do
      model = DummyModel.new(idx: "entity-123")

      assert_equal "entity-123", model.to_param
    end
  end
end
