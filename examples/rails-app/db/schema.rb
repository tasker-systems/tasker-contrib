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

ActiveRecord::Schema[8.1].define(version: 1) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "analytics_jobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "dataset_url"
    t.string "source", null: false
    t.string "status", default: "pending", null: false
    t.uuid "task_uuid"
    t.datetime "updated_at", null: false
    t.index ["source"], name: "index_analytics_jobs_on_source"
    t.index ["status"], name: "index_analytics_jobs_on_status"
    t.index ["task_uuid"], name: "index_analytics_jobs_on_task_uuid", unique: true, where: "(task_uuid IS NOT NULL)"
  end

  create_table "compliance_checks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "namespace", null: false
    t.string "order_ref", null: false
    t.string "status", default: "pending", null: false
    t.uuid "task_uuid"
    t.datetime "updated_at", null: false
    t.index ["namespace"], name: "index_compliance_checks_on_namespace"
    t.index ["order_ref"], name: "index_compliance_checks_on_order_ref"
    t.index ["status"], name: "index_compliance_checks_on_status"
    t.index ["task_uuid"], name: "index_compliance_checks_on_task_uuid", unique: true, where: "(task_uuid IS NOT NULL)"
  end

  create_table "orders", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "customer_email", null: false
    t.jsonb "items", default: [], null: false
    t.string "status", default: "pending", null: false
    t.uuid "task_uuid"
    t.decimal "total", precision: 12, scale: 2
    t.datetime "updated_at", null: false
    t.index ["customer_email"], name: "index_orders_on_customer_email"
    t.index ["status"], name: "index_orders_on_status"
    t.index ["task_uuid"], name: "index_orders_on_task_uuid", unique: true, where: "(task_uuid IS NOT NULL)"
  end

  create_table "service_requests", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "request_type", null: false
    t.jsonb "result", default: {}
    t.string "status", default: "pending", null: false
    t.uuid "task_uuid"
    t.datetime "updated_at", null: false
    t.string "user_id"
    t.index ["request_type"], name: "index_service_requests_on_request_type"
    t.index ["status"], name: "index_service_requests_on_status"
    t.index ["task_uuid"], name: "index_service_requests_on_task_uuid", unique: true, where: "(task_uuid IS NOT NULL)"
    t.index ["user_id"], name: "index_service_requests_on_user_id"
  end
end
