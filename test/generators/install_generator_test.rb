require "test_helper"
require "generators/funes/install_generator"
require "rails/generators/test_case"

class InstallGeneratorTest < Rails::Generators::TestCase
  tests Funes::Generators::InstallGenerator
  destination File.expand_path("../../tmp/generators", __dir__)

  setup :prepare_destination

  test "creates migration file" do
    run_generator

    assert_migration "db/migrate/create_funes_events_table.rb"
  end

  test "migration has correct class name" do
    run_generator

    assert_migration "db/migrate/create_funes_events_table.rb" do |migration|
      assert_match(/class CreateFunesEventsTable/, migration)
    end
  end

  test "creates event_entries table with id false" do
    run_generator

    assert_migration "db/migrate/create_funes_events_table.rb" do |migration|
      assert_match(/create_table :event_entries, id: false/, migration)
    end
  end

  test "has required columns" do
    run_generator

    assert_migration "db/migrate/create_funes_events_table.rb" do |migration|
      assert_match(/t\.column :klass, :string, null: false/, migration)
      assert_match(/t\.column :idx, :string, null: false/, migration)
      assert_match(/t\.column :props, :json, null: false/, migration)
      assert_match(/t\.column :meta_info, :json/, migration)
      assert_match(/t\.column :version, :bigint/, migration)
      assert_match(/t\.column :created_at, :datetime/, migration)
    end
  end

  test "has indexes" do
    run_generator

    assert_migration "db/migrate/create_funes_events_table.rb" do |migration|
      assert_match(/add_index :event_entries, :idx/, migration)
      assert_match(/add_index :event_entries, :created_at/, migration)
      assert_match(/add_index :event_entries, \[ :idx, :version \], unique: true/, migration)
    end
  end

  test "uses json column type for non-postgresql adapter" do
    run_generator

    assert_migration "db/migrate/create_funes_events_table.rb" do |migration|
      assert_match(/:json/, migration)
      assert_no_match(/:jsonb/, migration)
    end
  end
end
