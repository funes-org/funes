class AddDepositLastActivities < ActiveRecord::Migration[7.1]
  def change
    create_table :deposit_last_activities, id: false, primary_key: :idx do |t|
      t.string :idx, null: false
      t.integer :activity_type, null: false, default: 0
      t.date :creation_date, null: false
      t.date :activity_date, null: false
    end

    add_index :deposit_last_activities, :idx, unique: true
  end
end
