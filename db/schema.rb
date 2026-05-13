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

ActiveRecord::Schema[8.1].define(version: 2026_05_12_205455) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "panorama_projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "failure_reason"
    t.datetime "processing_finished_at"
    t.datetime "processing_started_at"
    t.string "status", default: "draft", null: false
    t.string "stitching_engine"
    t.text "stitching_logs"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_panorama_projects_on_status"
  end

  create_table "source_photos", force: :cascade do |t|
    t.string "content_type"
    t.datetime "created_at", null: false
    t.text "exif_data"
    t.bigint "file_size"
    t.string "filename"
    t.integer "height"
    t.integer "panorama_project_id", null: false
    t.integer "position", null: false
    t.datetime "updated_at", null: false
    t.string "validation_status"
    t.text "validation_warnings"
    t.integer "width"
    t.index ["panorama_project_id", "position"], name: "index_source_photos_on_panorama_project_id_and_position", unique: true
    t.index ["panorama_project_id"], name: "index_source_photos_on_panorama_project_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "source_photos", "panorama_projects", on_delete: :cascade
end
