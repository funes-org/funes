require "test_helper"
require "generators/funes/materialization_table_generator"
require "rails/generators/test_case"

class MaterializationTableGeneratorTest < Rails::Generators::TestCase
  tests Funes::Generators::MaterializationTableGenerator
  destination File.expand_path("../../tmp/generators", __dir__)

  setup :prepare_destination

  test "creates migration with idx primary key" do
    run_generator [ "DepositSummary" ]

    assert_migration "db/migrate/create_deposit_summaries.rb" do |migration|
      assert_match(/class CreateDepositSummaries/, migration)
      assert_match(/create_table :deposit_summaries, id: false, primary_key: :idx/, migration)
      assert_match(/t\.string :idx, null: false/, migration)
      assert_match(/add_index :deposit_summaries, :idx, unique: true/, migration)
    end
  end

  test "includes attribute columns" do
    run_generator [ "Order", "total:decimal", "status:integer" ]

    assert_migration "db/migrate/create_orders.rb" do |migration|
      assert_match(/t\.decimal :total/, migration)
      assert_match(/t\.integer :status/, migration)
    end
  end

  test "handles singular name" do
    run_generator [ "Account" ]

    assert_migration "db/migrate/create_accounts.rb" do |migration|
      assert_match(/class CreateAccounts/, migration)
      assert_match(/create_table :accounts/, migration)
    end
  end
end
