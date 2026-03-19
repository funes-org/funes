class AddDepositSnapshots < ActiveRecord::Migration[7.1]
  def change
    create_table :deposits, id: false, primary_key: :idx do |t|
      t.string :idx, null: false
      t.date :created_at, null: false
      t.decimal :original_value, null: false
      t.decimal :balance, null: false
      t.integer :status, null: false, default: 0
    end

    add_index :deposits, :idx, unique: true
  end
end
