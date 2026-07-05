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

ActiveRecord::Schema[8.1].define(version: 2026_07_01_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "boundaries", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "boundary_type", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.jsonb "properties", default: {}
    t.datetime "updated_at", null: false
    t.index ["active", "boundary_type"], name: "index_boundaries_on_active_and_boundary_type"
    t.index ["active"], name: "index_boundaries_on_active"
    t.index ["boundary_type"], name: "index_boundaries_on_boundary_type"
    t.index ["name"], name: "index_boundaries_on_name"
  end

  create_table "conversation_logs", force: :cascade do |t|
    t.text "ai_response", null: false
    t.datetime "created_at", null: false
    t.text "metadata"
    t.string "session_id", null: false
    t.text "tool_results"
    t.datetime "updated_at", null: false
    t.text "user_message", null: false
    t.index ["created_at"], name: "index_conversation_logs_on_created_at"
    t.index ["session_id"], name: "index_conversation_logs_on_session_id"
  end

  create_table "conversations", force: :cascade do |t|
    t.boolean "continue_conversation", default: true
    t.datetime "created_at", null: false
    t.string "end_reason"
    t.datetime "ended_at"
    t.text "flow_data"
    t.integer "message_count", default: 0
    t.text "metadata"
    t.string "persona"
    t.datetime "reflected_at"
    t.string "session_id", null: false
    t.string "source", default: "api"
    t.datetime "started_at"
    t.decimal "total_cost", precision: 10, scale: 6, default: "0.0"
    t.integer "total_tokens", default: 0
    t.datetime "updated_at", null: false
    t.index ["ended_at"], name: "index_conversations_on_ended_at"
    t.index ["persona"], name: "index_conversations_on_persona"
    t.index ["reflected_at"], name: "index_conversations_on_reflected_at"
    t.index ["session_id"], name: "index_conversations_on_session_id", unique: true
    t.index ["started_at"], name: "index_conversations_on_started_at"
  end

  create_table "landmarks", force: :cascade do |t|
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.text "description"
    t.string "icon"
    t.string "landmark_type"
    t.decimal "latitude", precision: 10, scale: 8, null: false
    t.decimal "longitude", precision: 11, scale: 8, null: false
    t.string "name", null: false
    t.jsonb "properties", default: {}
    t.integer "radius_meters", default: 30
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_landmarks_on_active"
    t.index ["landmark_type"], name: "index_landmarks_on_landmark_type"
    t.index ["latitude", "longitude"], name: "index_landmarks_on_latitude_and_longitude"
    t.index ["name"], name: "index_landmarks_on_name"
  end

  create_table "memories", force: :cascade do |t|
    t.string "category", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.vector "embedding", limit: 1536
    t.string "emotion"
    t.integer "importance", null: false
    t.text "metadata"
    t.datetime "occurs_at"
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_memories_on_category"
    t.index ["created_at"], name: "index_memories_on_created_at"
    t.index ["importance"], name: "index_memories_on_importance"
    t.index ["occurs_at"], name: "index_memories_on_occurs_at"
  end

  create_table "messages", force: :cascade do |t|
    t.integer "completion_tokens"
    t.text "content", null: false
    t.bigint "conversation_id", null: false
    t.decimal "cost", precision: 10, scale: 6
    t.datetime "created_at", null: false
    t.text "metadata"
    t.string "model_used"
    t.integer "prompt_tokens"
    t.string "role", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "created_at"], name: "index_messages_on_conversation_id_and_created_at"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["created_at"], name: "index_messages_on_created_at"
    t.index ["role"], name: "index_messages_on_role"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "streets", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.jsonb "properties", default: {}
    t.string "street_type", null: false
    t.datetime "updated_at", null: false
    t.integer "width", default: 30
    t.index ["active", "street_type"], name: "index_streets_on_active_and_street_type"
    t.index ["active"], name: "index_streets_on_active"
    t.index ["name"], name: "index_streets_on_name"
    t.index ["street_type"], name: "index_streets_on_street_type"
  end

  create_table "summaries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.vector "embedding", limit: 1536
    t.datetime "end_time"
    t.integer "message_count", null: false
    t.text "metadata"
    t.datetime "start_time"
    t.text "summary_text", null: false
    t.string "summary_type", null: false
    t.datetime "updated_at", null: false
    t.index ["end_time"], name: "index_summaries_on_end_time"
    t.index ["start_time"], name: "index_summaries_on_start_time"
    t.index ["summary_type"], name: "index_summaries_on_summary_type"
  end

  add_foreign_key "messages", "conversations"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
end
