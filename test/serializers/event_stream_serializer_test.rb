require "test_helper"
require "minitest/spec"

class EventStreamSerializerTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  let(:serializer) { Funes::EventStreamSerializer.instance }

  describe "#serialize?" do
    it "returns true for EventStream instances" do
      event_stream = Examples::DepositEventStream.for("test-id")
      assert serializer.serialize?(event_stream)
    end

    it "returns false for non-EventStream objects" do
      refute serializer.serialize?("test-id")
      refute serializer.serialize?(42)
    end
  end

  describe "serialize and deserialize round-trip" do
    it "round-trips an EventStream through serialization" do
      deserialized = serializer.deserialize(serializer.serialize(Examples::DepositEventStream.for("order-123")))

      assert_instance_of Examples::DepositEventStream, deserialized
      assert_equal "order-123", deserialized.idx
    end

    it "round-trips an EventStream through ActiveJob::Arguments with JSON encoding (simulating a real queue)" do
      event_stream = Examples::DepositEventStream.for("order-123")

      serialized = ActiveJob::Arguments.serialize([ event_stream ])
      over_the_wire = JSON.parse(JSON.dump(serialized))
      deserialized = ActiveJob::Arguments.deserialize(over_the_wire).first

      assert_instance_of Examples::DepositEventStream, deserialized
      assert_equal "order-123", deserialized.idx
    end
  end
end
