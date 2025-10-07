class CreateFunesEventsTable < ActiveRecord::Migration<%= migration_version %>
  def change
    create_table :events, id: false do |t|
      t.column :klass, :string, null: false
      t.column :entity_id, :string, null: false
      t.column :props, :<%= json_column_type %>, null: false
      t.column :version, :bigint, default: 1, null: false
      t.column :created_at, :datetime, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_index :events, :entity_id
    add_index :events, :created_at
    add_index :events, [:entity_id, :version], unique: true
  end
end