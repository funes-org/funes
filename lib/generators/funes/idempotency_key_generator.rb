require "rails/generators/base"
require "rails/generators/active_record"
require "generators/funes/database_adapter"

module Funes
  module Generators
    class IdempotencyKeyGenerator < Rails::Generators::Base
      include Rails::Generators::Migration
      include Funes::Generators::DatabaseAdapter

      source_root File.expand_path("templates", __dir__)
      desc "Creates a migration that adds the idempotency_key column to an existing Funes events table"

      def self.next_migration_number(dirname)
        ::ActiveRecord::Generators::Base.next_migration_number(dirname)
      end

      def create_migration_file
        migration_template("idempotency_key_migration.rb.tt",
                           "db/migrate/add_idempotency_key_to_funes_events_table.rb",
                           migration_version: migration_version)
      end

      private
        def migration_version
          "[#{::Rails::VERSION::MAJOR}.#{::Rails::VERSION::MINOR}]"
        end
    end
  end
end
