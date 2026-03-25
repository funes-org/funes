require "test_helper"
require "minitest/spec"

class EventMetainformationValidationTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  let(:event) { Examples::DepositEvents::Created.new(value: 10_000, effective_date: Time.current) }
  let(:idx) { "meta-#{SecureRandom.uuid}" }

  describe "when no metainformation is configured" do
    it "persists the event" do
      assert_difference -> { Funes::EventEntry.count }, 1 do
        Examples::DepositEventStream.for(idx).append(event)
      end

      assert event.persisted?
    end
  end

  describe "when only metainformation attributes are configured" do
    before do
      Funes.configure { |c| c.event_metainformation_attributes = [ :user_id, :action ] }
      Funes::EventMetainformation.setup_attributes!
    end

    it "persists the event with attributes set and its meta_info" do
      Funes::EventMetainformation.user_id = 123
      Funes::EventMetainformation.action = "tests#run"

      assert_difference -> { Funes::EventEntry.count }, 1 do
        Examples::DepositEventStream.for(idx).append(event)
      end

      assert event.persisted?
      assert_equal({ user_id: 123, action: "tests#run" }.stringify_keys,
                   Funes::EventEntry.order(created_at: :desc).first.meta_info)
    end

    it "persists the event with nil attributes" do
      assert_difference -> { Funes::EventEntry.count }, 1 do
        Examples::DepositEventStream.for(idx).append(event)
      end

      assert event.persisted?
      assert_empty Funes::EventEntry.order(created_at: :desc).first.meta_info
    end
  end

  describe "when metainformation attributes and validations are configured" do
    before do
      Funes.configure do |config|
        config.event_metainformation_attributes = [ :user_id, :action ]
        config.event_metainformation_validations do
          validates :user_id, presence: true
          validates :action, presence: true, format: { with: /\A\w+#\w+\z/ }
        end
      end
    end

    describe "with valid metainformation" do
      before do
        Funes::EventMetainformation.setup_attributes!
        Funes::EventMetainformation.user_id = 123
        Funes::EventMetainformation.action = "tests#run"
      end

      it "persists the event and its meta_info" do
        assert_difference -> { Funes::EventEntry.count }, 1 do
          Examples::DepositEventStream.for(idx).append(event)
        end

        assert event.persisted?
        assert_equal({ user_id: 123, action: "tests#run" }.stringify_keys,
                     Funes::EventEntry.order(created_at: :desc).first.meta_info)
      end
    end

    describe "when presence validation fails" do
      before do
        Funes::EventMetainformation.setup_attributes!
        Funes::EventMetainformation.user_id = nil
        Funes::EventMetainformation.action = "tests#run"
      end

      it "raises InvalidEventMetainformation and does not persist the event" do
        assert_no_difference -> { Funes::EventEntry.count } do
          assert_raises(Funes::InvalidEventMetainformation) { Examples::DepositEventStream.for(idx).append(event) }
        end

        refute event.persisted?
      end
    end

    describe "when format validation fails" do
      before do
        Funes::EventMetainformation.setup_attributes!
        Funes::EventMetainformation.user_id = 123
        Funes::EventMetainformation.action = "invalid-format"
      end

      it "raises InvalidEventMetainformation and does not persist the event" do
        assert_no_difference -> { Funes::EventEntry.count } do
          assert_raises(Funes::InvalidEventMetainformation) { Examples::DepositEventStream.for(idx).append(event) }
        end

        refute event.persisted?
      end
    end
  end

  teardown do
    Funes::EventMetainformation.reset
    Funes::EventMetainformation.clear_validators!
    Funes.instance_variable_set(:@configuration, Funes::Configuration.new)
  end
end
