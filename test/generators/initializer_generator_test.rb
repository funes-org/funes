require "test_helper"
require "generators/funes/initializer_generator"
require "rails/generators/test_case"

class InitializerGeneratorTest < Rails::Generators::TestCase
  tests Funes::Generators::InitializerGenerator
  destination File.expand_path("../../tmp/generators", __dir__)

  setup :prepare_destination

  test "creates initializer file" do
    run_generator

    assert_file "config/initializers/funes.rb"
  end

  test "initializer contains configure block" do
    run_generator

    assert_file "config/initializers/funes.rb" do |content|
      assert_match(/Funes\.configure do \|config\|/, content)
    end
  end

  test "initializer includes commented metainformation configuration" do
    run_generator

    assert_file "config/initializers/funes.rb" do |content|
      assert_match(/config\.event_metainformation_attributes/, content)
      assert_match(/config\.event_metainformation_validations/, content)
    end
  end
end
