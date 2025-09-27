class RemoveUnnecessaryTables < ActiveRecord::Migration[8.0]
  def change
    drop_table(:debt_collections_projections)
  end
end
