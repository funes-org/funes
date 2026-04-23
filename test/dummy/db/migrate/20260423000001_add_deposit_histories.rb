class AddDepositHistories < ActiveRecord::Migration[7.1]
  def change
    create_table :deposit_histories, id: false, primary_key: [ :idx, :version ] do |t|
      t.string :idx, null: false
      t.string :version, null: false
      t.decimal :balance, null: false
    end

    add_index :deposit_histories, [ :idx, :version ], unique: true
  end
end
