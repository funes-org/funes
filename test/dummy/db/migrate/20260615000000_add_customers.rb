class AddCustomers < ActiveRecord::Migration[7.1]
  def change
    create_table :customers do |t|
      t.string :name

      t.timestamps
    end
  end
end
