require "test_helper"
require "minitest/spec"
require "pp"

class Funes::InspectionTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  class InspectableEvent < Funes::Event
    attribute :name, :string
    attribute :age, :integer
    attribute :bio, :string
    attribute :total, :decimal
    attribute :born_on, :date
    attribute :created_at, :datetime
    attribute :password, :string
  end

  describe "#inspect" do
    it "shows all attributes in #<ClassName ...> format" do
      event = InspectableEvent.new(name: "Alice", age: 30)

      assert_match(/^#<Funes::InspectionTest::InspectableEvent /, event.inspect)
      assert_includes event.inspect, 'name: "Alice"'
      assert_includes event.inspect, "age: 30"
    end

    it "does not leak internal accessors" do
      event = InspectableEvent.new(name: "Alice")

      refute_includes event.inspect, "_adjacent_state_errors"
      refute_includes event.inspect, "_interpretation_errors"
      refute_includes event.inspect, "_event_entry"
    end

    it "truncates strings longer than 50 characters" do
      long_string = "a" * 60
      event = InspectableEvent.new(name: long_string)

      assert_includes event.inspect, "#{"a" * 50}..."
      refute_includes event.inspect, "a" * 51
    end

    it "formats date values" do
      event = InspectableEvent.new(born_on: Date.new(2024, 1, 15))

      assert_includes event.inspect, "born_on:"
      assert_includes event.inspect, "2024"
    end

    it "formats datetime values" do
      event = InspectableEvent.new(created_at: Time.utc(2024, 1, 15, 10, 30, 0))

      assert_includes event.inspect, "created_at:"
      assert_includes event.inspect, "2024"
    end

    it "shows nil for nil values" do
      event = InspectableEvent.new(name: nil)

      assert_includes event.inspect, "name: nil"
    end

    it "formats decimal values without scientific notation" do
      event = InspectableEvent.new(total: 99.99)

      assert_includes event.inspect, "total: 99.99"
      refute_includes event.inspect, "0.9999e2"
    end

    it "handles uninitialized (allocate) gracefully" do
      event = InspectableEvent.allocate

      assert_includes event.inspect, "not initialized"
    end
  end

  describe ".filter_attributes" do
    teardown do
      InspectableEvent.filter_attributes = nil
    end

    it "loads filter_parameters from Rails app configuration" do
      assert_equal Rails.application.config.filter_parameters, Funes::Event.filter_attributes
    end

    it "masks values for symbol filter" do
      InspectableEvent.filter_attributes = [ :password ]
      event = InspectableEvent.new(name: "Alice", password: "secret")

      assert_includes event.inspect, "password: [FILTERED]"
      refute_includes event.inspect, "secret"
    end

    it "masks values for regex filter" do
      InspectableEvent.filter_attributes = [ /pass/ ]
      event = InspectableEvent.new(name: "Alice", password: "secret")

      assert_includes event.inspect, "password: [FILTERED]"
      refute_includes event.inspect, "secret"
    end

    it "masks values for proc filter" do
      InspectableEvent.filter_attributes = [ ->(key, value) { value.replace("[CUSTOM]") if key == "password" } ]
      event = InspectableEvent.new(name: "Alice", password: "secret")

      assert_includes event.inspect, "password: [CUSTOM]"
      refute_includes event.inspect, "secret"
    end

    it "inherits filter_attributes from superclass" do
      InspectableEvent.filter_attributes = [ :password ]
      subclass = Class.new(InspectableEvent)
      event = subclass.new(name: "Alice", password: "secret")

      assert_includes event.inspect, "[FILTERED]"
    end

    it "allows subclass to override filter_attributes" do
      InspectableEvent.filter_attributes = [ :password ]
      subclass = Class.new(InspectableEvent)
      subclass.filter_attributes = [ :name ]
      event = subclass.new(name: "Alice", password: "secret")

      assert_includes event.inspect, 'password: "secret"'
      assert_includes event.inspect, "name: [FILTERED]"
    end
  end

  describe ".attributes_for_inspect" do
    teardown do
      InspectableEvent.attributes_for_inspect = :all
    end

    it "limits output to listed attributes" do
      InspectableEvent.attributes_for_inspect = [ :name, :age ]
      event = InspectableEvent.new(name: "Alice", age: 30, bio: "Developer")

      assert_includes event.inspect, "name:"
      assert_includes event.inspect, "age:"
      refute_includes event.inspect, "bio:"
    end
  end

  describe "#full_inspect" do
    teardown do
      InspectableEvent.attributes_for_inspect = :all
    end

    it "shows all attributes even when attributes_for_inspect is limited" do
      InspectableEvent.attributes_for_inspect = [ :name ]
      event = InspectableEvent.new(name: "Alice", age: 30)

      refute_includes event.inspect, "age:"
      assert_includes event.full_inspect, "age: 30"
      assert_includes event.full_inspect, 'name: "Alice"'
    end
  end

  describe "#attribute_for_inspect" do
    it "returns formatted value for a single attribute" do
      event = InspectableEvent.new(name: "Alice", age: 30)

      assert_equal '"Alice"', event.attribute_for_inspect(:name)
      assert_equal "30", event.attribute_for_inspect(:age)
    end

    it "returns nil for nil attribute" do
      event = InspectableEvent.new(name: nil)

      assert_equal "nil", event.attribute_for_inspect(:name)
    end

    it "truncates long strings" do
      event = InspectableEvent.new(name: "a" * 60)

      assert_includes event.attribute_for_inspect(:name), "..."
    end
  end

  describe "#pretty_print" do
    it "produces formatted output via pp" do
      event = InspectableEvent.new(name: "Alice", age: 30)
      output = PP.pp(event, StringIO.new).string

      assert_includes output, "InspectableEvent"
      assert_includes output, "name:"
      assert_includes output, "age:"
    end

    it "respects filter_attributes" do
      InspectableEvent.filter_attributes = [ :password ]
      event = InspectableEvent.new(name: "Alice", password: "secret")
      output = PP.pp(event, StringIO.new).string

      assert_includes output, "[FILTERED]"
      refute_includes output, "secret"

      InspectableEvent.filter_attributes = nil
    end

    it "handles uninitialized (allocate) gracefully" do
      event = InspectableEvent.allocate
      output = PP.pp(event, StringIO.new).string

      assert_includes output, "not initialized"
    end
  end
end
