require "rails/generators/base"
require "rails/generators/active_record"

module Funes
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)
      desc "Funes rules!!!"

      def self.next_migration_number(dirname)
        ::ActiveRecord::Generators::Base.next_migration_number(dirname)
      end

      def create_migration_file
        migration_template("migration.rb",
                           "db/migrate/create_funes_events_table.rb",
                           migration_version: migration_version)
      end

      def show_readme
        readme "README.md" if File.exist?(File.join(self.class.source_root, "README.md"))
      end

      private
        def json_column_type
          postgres? ? "jsonb" : "json"
        end

        def migration_version
          "[#{::Rails::VERSION::MAJOR}.#{::Rails::VERSION::MINOR}]"
        end

        def postgres?
          ActiveRecord::Base.configurations.configs_for(env_name: Rails.env).first&.adapter == "postgresql"
        end
    end
  end
end
