# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_09_18_023414) do
  create_table "debt_collections_projections", id: false, force: :cascade do |t|
    t.string "idx", null: false
    t.decimal "outstanding_balance", precision: 15, scale: 2, null: false
    t.date "issuance_date", null: false
    t.date "last_payment_date"
    t.index [ "idx" ], name: "index_debt_collections_projections_on_idx", unique: true
  end

  create_table "materializations", id: false, force: :cascade do |t|
    t.integer "value", null: false
    t.string "idx", null: false
    t.index [ "idx" ], name: "index_materializations_on_idx", unique: true
  end
end
