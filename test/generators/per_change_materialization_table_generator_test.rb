require "test_helper"
require "generators/funes/per_change_materialization_table_generator"
require "rails/generators/test_case"

class PerChangeMaterializationTableGeneratorTest < Rails::Generators::TestCase
  tests Funes::Generators::PerChangeMaterializationTableGenerator
  destination File.expand_path("../../tmp/generators", __dir__)

  setup :prepare_destination

  test "creates migration with (idx, version) composite primary key" do
    run_generator [ "BalanceHistory" ]

    assert_migration "db/migrate/create_balance_histories.rb" do |migration|
      assert_match(/class CreateBalanceHistories/, migration)
      assert_match(/create_table :balance_histories, id: false, primary_key: \[:idx, :version\]/, migration)
      assert_match(/t\.string :idx, null: false/, migration)
      assert_match(/t\.string :version, null: false/, migration)
      assert_match(/add_index :balance_histories, \[:idx, :version\], unique: true/, migration)
    end
  end

  test "includes attribute columns" do
    run_generator [ "LedgerEntry", "amount:decimal", "memo:string" ]

    assert_migration "db/migrate/create_ledger_entries.rb" do |migration|
      assert_match(/t\.decimal :amount/, migration)
      assert_match(/t\.string :memo/, migration)
    end
  end

  test "handles singular name" do
    run_generator [ "Position" ]

    assert_migration "db/migrate/create_positions.rb" do |migration|
      assert_match(/class CreatePositions/, migration)
      assert_match(/create_table :positions/, migration)
    end
  end
end
