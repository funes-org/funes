class AddEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :event_entries, id: false do |t|
      t.column :klass, :string, null: false
      t.column :idx, :string, null: false
      t.column :props, :json, null: false
      t.column :meta_info, :json
      t.column :version, :bigint, default: 1, null: false
      t.column :created_at, :datetime, null: false
    end

    add_index :event_entries, :idx
    add_index :event_entries, :created_at
    add_index :event_entries, [ :idx, :version ], unique: true
  end
end
