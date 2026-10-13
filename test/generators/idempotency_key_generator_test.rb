require "test_helper"
require "generators/funes/idempotency_key_generator"
require "rails/generators/test_case"

class IdempotencyKeyGeneratorTest < Rails::Generators::TestCase
  tests Funes::Generators::IdempotencyKeyGenerator
  destination File.expand_path("../../tmp/generators", __dir__)

  setup :prepare_destination

  test "creates a migration that adds the nullable column and the unique index" do
    run_generator

    assert_migration "db/migrate/add_idempotency_key_to_funes_events_table.rb" do |migration|
      assert_match(/class AddIdempotencyKeyToFunesEventsTable/, migration)
      assert_match(/add_column :event_entries, :idempotency_key, :string$/, migration)
      assert_match(/add_index :event_entries, :idempotency_key, unique: true, where: "idempotency_key IS NOT NULL"$/,
                   migration)
    end
  end

  test "writes a partial index on postgresql" do
    with_adapter("postgresql") { run_generator }

    assert_migration "db/migrate/add_idempotency_key_to_funes_events_table.rb" do |migration|
      assert_match(/add_index :event_entries, :idempotency_key, unique: true, where: "idempotency_key IS NOT NULL"$/,
                   migration)
    end
  end

  test "writes a full index on mysql, which has no partial indexes" do
    with_adapter("mysql2") { run_generator }

    assert_migration "db/migrate/add_idempotency_key_to_funes_events_table.rb" do |migration|
      assert_match(/add_index :event_entries, :idempotency_key, unique: true$/, migration)
      assert_no_match(/where:/, migration)
    end
  end

  private
    # The generators read the adapter name from the database configuration, not from a connection.
    def with_adapter(adapter, &block)
      config = Struct.new(:adapter).new(adapter)
      configurations = Struct.new(:config) { def configs_for(**) = [ config ] }.new(config)

      ActiveRecord::Base.stub(:configurations, configurations, &block)
    end
end
