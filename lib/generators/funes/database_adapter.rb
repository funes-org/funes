module Funes
  module Generators
    # Adapter-dependent choices shared by the generators that write the events table migrations.
    # They read the configured adapter name instead of opening a connection, so a generator runs
    # before the database exists.
    module DatabaseAdapter
      private
        def adapter_name
          ActiveRecord::Base.configurations.configs_for(env_name: Rails.env).first&.adapter
        end

        def postgres?
          adapter_name == "postgresql"
        end

        def json_column_type
          postgres? ? "jsonb" : "json"
        end

        # Only PostgreSQL and SQLite support partial indexes. MySQL gets a full index, which also
        # holds one entry per event without a key.
        def supports_partial_index?
          %w[postgresql sqlite3].include?(adapter_name)
        end

        def idempotency_key_index_options
          supports_partial_index? ? ', where: "idempotency_key IS NOT NULL"' : ""
        end
    end
  end
end
