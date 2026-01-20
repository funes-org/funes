require "test_helper"
require "minitest/spec"

class Funes::EventMetainformationBuilderTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  describe "#validates" do
    it "collects validation definitions with options" do
      builder = Funes::EventMetainformationBuilder.new

      builder.validates :user_id, presence: true
      builder.validates :action, format: { with: /\A\w+\z/ }

      assert_equal 2, builder.validations.size
      assert_equal [ [ :user_id ], { presence: true } ], builder.validations[0]
      assert_equal [ [ :action ], { format: { with: /\A\w+\z/ } } ], builder.validations[1]
    end

    it "supports multiple validators in single call" do
      builder = Funes::EventMetainformationBuilder.new

      builder.validates :code, presence: true, length: { minimum: 3 }

      assert_equal [ [ [ :code ], { presence: true, length: { minimum: 3 } } ] ], builder.validations
    end
  end

  describe "#evaluate" do
    it "evaluates block in builder context" do
      builder = Funes::EventMetainformationBuilder.new

      builder.evaluate do
        validates :user_id, presence: true
        validates :action, format: { with: /\A\w+\z/ }
      end

      assert_equal 2, builder.validations.size
    end
  end
end
