class AddAccounts < ActiveRecord::Migration[7.1]
  def change
    create_table :accounts do |t|
      t.string :number

      t.timestamps
    end
  end
end
