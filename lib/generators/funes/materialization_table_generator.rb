require "rails/generators/base"
require "rails/generators/active_record"

module Funes
  module Generators
    class MaterializationTableGenerator < Rails::Generators::NamedBase
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)
      desc "Creates a migration for a Funes materialization table"

      argument :attributes, type: :array, default: [], banner: "field:type field:type"

      def self.next_migration_number(dirname)
        ::ActiveRecord::Generators::Base.next_migration_number(dirname)
      end

      def create_migration_file
        migration_template(
          "materialization_table.rb.tt",
          "db/migrate/create_#{table_name}.rb",
          migration_version: migration_version
        )
      end

      private
        def migration_version
          "[#{::Rails::VERSION::MAJOR}.#{::Rails::VERSION::MINOR}]"
        end

        def table_name
          file_name.tableize
        end
    end
  end
end
