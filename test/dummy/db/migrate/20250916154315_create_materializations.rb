class CreateMaterializations < ActiveRecord::Migration[8.0]
  def change
    create_table :materializations, id: false, primary_key: :idx do |t|
      t.integer :value, null: false
      t.string :idx, null: false
    end

    add_index :materializations, :idx, unique: true
  end
end
