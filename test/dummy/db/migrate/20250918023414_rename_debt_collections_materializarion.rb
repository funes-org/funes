class RenameDebtCollectionsProjection < ActiveRecord::Migration[8.0]
  def change
    rename_table :debt_collections_materializations, :debt_collections_projections
  end
end
