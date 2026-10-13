class AddIdempotencyKeyToEventEntries < ActiveRecord::Migration[7.1]
  def change
    add_column :event_entries, :idempotency_key, :string
    add_index :event_entries, :idempotency_key, unique: true, where: "idempotency_key IS NOT NULL"
  end
end
