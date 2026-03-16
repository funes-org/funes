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

ActiveRecord::Schema[7.1].define(version: 2026_03_11_190825) do
  create_table "deposit_last_activities", id: false, force: :cascade do |t|
    t.string "idx", null: false
    t.integer "activity_type", default: 0, null: false
    t.date "creation_date", null: false
    t.date "activity_date", null: false
    t.index ["idx"], name: "index_deposit_last_activities_on_idx", unique: true
  end

  create_table "deposits", id: false, force: :cascade do |t|
    t.string "idx", null: false
    t.date "created_at", null: false
    t.decimal "original_value", null: false
    t.decimal "balance", null: false
    t.integer "status", default: 0, null: false
    t.index ["idx"], name: "index_deposits_on_idx", unique: true
  end

  create_table "event_entries", id: false, force: :cascade do |t|
    t.string "klass", null: false
    t.string "idx", null: false
    t.json "props", null: false
    t.json "meta_info"
    t.bigint "version", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "occurred_at", null: false
    t.index ["created_at"], name: "index_event_entries_on_created_at"
    t.index ["idx", "version"], name: "index_event_entries_on_idx_and_version", unique: true
    t.index ["idx"], name: "index_event_entries_on_idx"
    t.index ["occurred_at"], name: "index_event_entries_on_occurred_at"
  end
end
