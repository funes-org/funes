require "test_helper"
require "minitest/spec"

class Funes::EventTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  class DummyEvent < Funes::Event
    attribute :value, :integer
  end

  describe "#persisted?" do
    it "returns false for a new event" do
      event = DummyEvent.new(value: 42)

      refute event.persisted?
    end

    it "returns true when _event_entry is set" do
      event = DummyEvent.new(value: 42)
      event._event_entry = Funes::EventEntry.new

      assert event.persisted?
    end

    it "returns false when _event_entry is nil" do
      event = DummyEvent.new(value: 42)
      event._event_entry = nil

      refute event.persisted?
    end
  end

  describe "#created_at" do
    it "returns nil for a new event" do
      event = DummyEvent.new(value: 42)
      assert_nil event.created_at
    end

    it "returns the _event_entry created_at when persisted" do
      event = DummyEvent.new(value: 42)
      event._event_entry = Funes::EventEntry.new(created_at: Time.current)
      assert_equal event._event_entry.created_at, event.created_at
    end

    it "returns the timestamp set by the database when persisted" do
      frozen_time = Time.current.change(usec: 0)
      event = DummyEvent.new(value: 42)
      travel_to frozen_time do
        event.persist!("created-at-idx", 1)
        assert_equal frozen_time, event.created_at
      end
    end
  end

  describe "#occurred_at" do
    it "returns nil for a new event" do
      event = DummyEvent.new(value: 42)
      assert_nil event.occurred_at
    end

    it "returns the _event_entry occurred_at when persisted" do
      event = DummyEvent.new(value: 42)
      event._event_entry = Funes::EventEntry.new(occurred_at: Time.current)
      assert_equal event._event_entry.occurred_at, event.occurred_at
    end

    it "defaults to created_at when at: is not provided" do
      frozen_time = Time.current.change(usec: 0)
      event = DummyEvent.new(value: 42)
      travel_to frozen_time do
        event.persist!("occurred-at-default-idx", 1)
        assert_equal event.created_at, event.occurred_at
      end
    end

    it "uses the at: value when provided" do
      event = DummyEvent.new(value: 42)
      explicit_time = Time.new(2025, 2, 15, 12, 0, 0)
      event.persist!("occurred-at-explicit-idx", 1, at: explicit_time)
      assert_equal explicit_time, event.occurred_at
    end
  end

  describe "#persist!" do
    it "raises InvalidEventMetainformation when metainformation is invalid" do
      Funes.configure do |config|
        config.event_metainformation_attributes = [ :user_id ]

        config.event_metainformation_validations do
          validates :user_id, presence: true
        end
      end

      Funes::EventMetainformation.setup_attributes!
      Funes::EventMetainformation.user_id = nil

      event = DummyEvent.new(value: 42)

      error = assert_raises(Funes::InvalidEventMetainformation) do
        event.persist!("test-idx", 1)
      end

      assert_not event.persisted?
      assert_match(/can't be blank/, error.message)
    end

    it "persists when metainformation is valid" do
      Funes.configure do |config|
        config.event_metainformation_attributes = [ :user_id ]

        config.event_metainformation_validations do
          validates :user_id, presence: true
        end
      end

      Funes::EventMetainformation.setup_attributes!
      Funes::EventMetainformation.user_id = 123

      event = DummyEvent.new(value: 42)
      event.persist!("test-idx", 1)

      assert event.persisted?
    end

    it "persists when no metainformation validations are configured" do
      event = DummyEvent.new(value: 42)
      event.persist!("test-idx", 1)

      assert event.persisted?
    end
  end

  describe "#interpretation_errors" do
    it "is initialized as empty" do
      event = DummyEvent.new(value: 42)

      assert_empty event._interpretation_errors
    end

    it "accumulates errors via add" do
      event = DummyEvent.new(value: 42)
      event._interpretation_errors.add(:base, "first error")
      event._interpretation_errors.add(:value, "second error")

      assert_equal event._interpretation_errors.messages, { base: [ "first error" ], value: [ "second error" ] }
    end

    it "makes valid? return false when populated" do
      event = DummyEvent.new(value: 42)
      assert event.valid?

      event._interpretation_errors.add(:base, "rejected")
      refute event.valid?
    end

    it "appears in merged errors" do
      event = DummyEvent.new(value: 42)
      event._interpretation_errors.add(:base, "business rule violated")

      assert_equal 1, event.errors.size
      assert_includes "business rule violated", event.errors.first.message
    end

    it "returns interpretation_errors from own_errors" do
      event = DummyEvent.new(value: 42)
      event._interpretation_errors.add(:base, "rejected")

      assert_equal 1, event.own_errors.size
      assert_equal "rejected", event.own_errors.first.message
    end
  end

  teardown do
    Funes::EventMetainformation.reset
    Funes::EventMetainformation.clear_validators!
    Funes.instance_variable_set(:@configuration, Funes::Configuration.new)
  end
end
