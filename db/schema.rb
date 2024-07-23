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

ActiveRecord::Schema[7.1].define(version: 2024_07_23_204740) do
  create_table "content_genres", force: :cascade do |t|
    t.integer "content_id"
    t.integer "genre_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "contents", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.string "poster_url"
    t.string "trailer_url"
    t.string "source_id"
    t.string "source"
    t.integer "release_year"
    t.string "content_type"
    t.text "plot_keywords"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "genres", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "survey_questions", force: :cascade do |t|
    t.string "question_text"
    t.string "question_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "survey_responses", force: :cascade do |t|
    t.integer "survey_question_id"
    t.string "response"
    t.integer "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "user_preferences", force: :cascade do |t|
    t.integer "user_id", null: false
    t.json "personality_profiles"
    t.json "favorite_genres"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_user_preferences_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name"
    t.string "gender"
    t.date "dob"
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "user_preferences", "users"
end
