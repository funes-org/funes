require "test_helper"
require "minitest/spec"

class EventMetainformationValidationTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  module Events
    class SimpleEvent < Funes::Event
      attribute :value, :integer
    end
  end

  class SimpleProjection < Funes::Projection
    materialization_model UnitTests::Materialization

    interpretation_for Events::SimpleEvent do |state, event, _as_of|
      state.assign_attributes(value: event.value)
      state
    end
  end

  class TestEventStream < Funes::EventStream
    add_transactional_projection SimpleProjection
  end

  describe "when no metainformation is configured" do
    it "persists the event successfully" do
      idx = "meta-none-#{SecureRandom.uuid}"
      event = Events::SimpleEvent.new(value: 42)

      assert_difference -> { Funes::EventEntry.count }, 1 do
        TestEventStream.for(idx).append(event)
      end

      assert event.persisted?, "Event should be marked as persisted"
      assert event.errors.empty?, "Event should have no errors"
    end
  end

  describe "when only metainformation attributes are configured (no validations)" do
    it "persists the event successfully with attributes set" do
      Funes.configure do |config|
        config.event_metainformation_attributes = [ :user_id, :action ]
      end

      Funes::EventMetainformation.setup_attributes!
      Funes::EventMetainformation.user_id = 123
      Funes::EventMetainformation.action = "tests#run"

      idx = "meta-attrs-only-#{SecureRandom.uuid}"
      event = Events::SimpleEvent.new(value: 42)

      assert_difference -> { Funes::EventEntry.count }, 1 do
        TestEventStream.for(idx).append(event)
      end

      assert event.persisted?, "Event should be marked as persisted"
      assert event.errors.empty?, "Event should have no errors"
    end

    it "persists the event successfully even with nil attributes" do
      Funes.configure do |config|
        config.event_metainformation_attributes = [ :user_id, :action ]
      end

      Funes::EventMetainformation.setup_attributes!
      Funes::EventMetainformation.user_id = nil
      Funes::EventMetainformation.action = nil

      idx = "meta-attrs-nil-#{SecureRandom.uuid}"
      event = Events::SimpleEvent.new(value: 42)

      assert_difference -> { Funes::EventEntry.count }, 1 do
        TestEventStream.for(idx).append(event)
      end

      assert event.persisted?, "Event should be marked as persisted"
    end
  end

  describe "when metainformation attributes and validations are configured" do
    it "persists the event when metainformation is valid" do
      Funes.configure do |config|
        config.event_metainformation_attributes = [ :user_id, :action ]

        config.event_metainformation_validations do
          validates :user_id, presence: true
          validates :action, presence: true, format: { with: /\A\w+#\w+\z/ }
        end
      end

      Funes::EventMetainformation.setup_attributes!
      Funes::EventMetainformation.user_id = 123
      Funes::EventMetainformation.action = "tests#run"

      idx = "meta-valid-#{SecureRandom.uuid}"
      event = Events::SimpleEvent.new(value: 42)

      assert_difference -> { Funes::EventEntry.count }, 1 do
        TestEventStream.for(idx).append(event)
      end

      assert event.persisted?, "Event should be marked as persisted"
      assert event.errors.empty?, "Event should have no errors"
    end

    it "raises InvalidEventMetainformation when presence validation fails" do
      Funes.configure do |config|
        config.event_metainformation_attributes = [ :user_id ]

        config.event_metainformation_validations do
          validates :user_id, presence: true
        end
      end

      Funes::EventMetainformation.setup_attributes!
      Funes::EventMetainformation.user_id = nil

      idx = "meta-invalid-presence-#{SecureRandom.uuid}"
      event = Events::SimpleEvent.new(value: 42)

      assert_no_difference -> { Funes::EventEntry.count } do
        assert_raises(Funes::InvalidEventMetainformation) do
          TestEventStream.for(idx).append(event)
        end
      end

      refute event.persisted?, "Event should NOT be marked as persisted"
    end

    it "raises InvalidEventMetainformation when format validation fails" do
      Funes.configure do |config|
        config.event_metainformation_attributes = [ :action ]

        config.event_metainformation_validations do
          validates :action, format: { with: /\A\w+#\w+\z/ }
        end
      end

      Funes::EventMetainformation.setup_attributes!
      Funes::EventMetainformation.action = "invalid-format"

      idx = "meta-invalid-format-#{SecureRandom.uuid}"
      event = Events::SimpleEvent.new(value: 42)

      assert_no_difference -> { Funes::EventEntry.count } do
        assert_raises(Funes::InvalidEventMetainformation) do
          TestEventStream.for(idx).append(event)
        end
      end

      refute event.persisted?, "Event should NOT be marked as persisted"
    end

    it "does not create materialization when metainformation validation fails" do
      Funes.configure do |config|
        config.event_metainformation_attributes = [ :user_id ]

        config.event_metainformation_validations do
          validates :user_id, presence: true
        end
      end

      Funes::EventMetainformation.setup_attributes!
      Funes::EventMetainformation.user_id = nil

      idx = "meta-no-materialization-#{SecureRandom.uuid}"
      event = Events::SimpleEvent.new(value: 42)

      assert_no_difference -> { UnitTests::Materialization.count } do
        assert_raises(Funes::InvalidEventMetainformation) do
          TestEventStream.for(idx).append(event)
        end
      end

      refute UnitTests::Materialization.exists?(idx: idx), "Materialization should not exist"
    end
  end

  teardown do
    Funes::EventMetainformation.reset
    Funes::EventMetainformation.clear_validators!
    Funes.instance_variable_set(:@configuration, Funes::Configuration.new)
  end
end
