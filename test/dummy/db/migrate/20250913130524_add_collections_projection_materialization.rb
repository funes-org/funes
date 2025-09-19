class AddCollectionsProjectionMaterialization < ActiveRecord::Migration[8.0]
  def change
    create_table :debt_collections_materializations, id: false, primary_key: :idx do |t|
      t.string :idx, null: false
      t.decimal :outstanding_balance, precision: 15, scale: 2, null: false
      t.date :issuance_date, null: false
      t.date :last_payment_date, null: true
    end

    add_index(:debt_collections_materializations, :idx, unique: true)
  end
end
