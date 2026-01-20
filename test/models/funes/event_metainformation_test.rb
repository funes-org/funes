require "test_helper"
require "minitest/spec"

class Funes::EventMetainformationTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  describe ".setup_attributes!" do
    it "defines attributes from configuration array" do
      Funes.configuration.event_metainformation_attributes = [ :user_id, :request_id ]

      Funes::EventMetainformation.setup_attributes!

      assert_respond_to Funes::EventMetainformation, :user_id
      assert_respond_to Funes::EventMetainformation, :user_id=
      assert_respond_to Funes::EventMetainformation, :request_id
      assert_respond_to Funes::EventMetainformation, :request_id=
    end

    it "allows setting and reading attribute values" do
      Funes.configuration.event_metainformation_attributes = [ :user_id ]

      Funes::EventMetainformation.setup_attributes!
      Funes::EventMetainformation.user_id = 123

      assert_equal 123, Funes::EventMetainformation.user_id
    end

    it "applies presence validation from validations block" do
      Funes.configure do |config|
        config.event_metainformation_attributes = [ :user_id ]

        config.event_metainformation_validations do
          validates :user_id, presence: true
        end
      end

      Funes::EventMetainformation.setup_attributes!
      Funes::EventMetainformation.user_id = nil

      assert_not Funes::EventMetainformation.valid?
      assert_includes Funes::EventMetainformation.errors[:user_id], "can't be blank"
    end

    it "applies format validation from validations block" do
      Funes.configure do |config|
        config.event_metainformation_attributes = [ :action ]

        config.event_metainformation_validations do
          validates :action, format: { with: /\A\w+#\w+\z/ }
        end
      end

      Funes::EventMetainformation.setup_attributes!

      Funes::EventMetainformation.action = "invalid"
      assert_not Funes::EventMetainformation.valid?

      Funes::EventMetainformation.action = "users#show"
      assert Funes::EventMetainformation.valid?
    end

    it "applies length validation from validations block" do
      Funes.configure do |config|
        config.event_metainformation_attributes = [ :code ]

        config.event_metainformation_validations do
          validates :code, length: { minimum: 3, maximum: 10 }
        end
      end

      Funes::EventMetainformation.setup_attributes!

      Funes::EventMetainformation.code = "ab"
      assert_not Funes::EventMetainformation.valid?

      Funes::EventMetainformation.code = "abc"
      assert Funes::EventMetainformation.valid?

      Funes::EventMetainformation.code = "a" * 11
      assert_not Funes::EventMetainformation.valid?
    end
  end

  teardown do
    Funes::EventMetainformation.reset
    Funes::EventMetainformation.clear_validators!
    Funes.instance_variable_set(:@configuration, Funes::Configuration.new)
  end
end
