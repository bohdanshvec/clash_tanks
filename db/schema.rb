ActiveRecord::Schema[8.1].define(version: 2026_09_09_062246) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "abilities", force: :cascade do |t|
    t.string "code"
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_abilities_on_code", unique: true
  end

  create_table "cards", force: :cascade do |t|
    t.string "card_type"
    t.datetime "created_at", null: false
    t.string "name"
    t.bigint "nation_id", null: false
    t.datetime "updated_at", null: false
    t.integer "weight"
    t.index ["nation_id"], name: "index_cards_on_nation_id"
  end

  create_table "game_players", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "game_id", null: false
    t.bigint "player_id", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id", "player_id"], name: "index_game_players_on_game_id_and_player_id", unique: true
    t.index ["game_id"], name: "index_game_players_on_game_id"
    t.index ["player_id"], name: "index_game_players_on_player_id"
  end

  create_table "games", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "state"
    t.string "status"
    t.datetime "updated_at", null: false
  end

  create_table "nations", force: :cascade do |t|
    t.string "code"
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_nations_on_code", unique: true
  end

  create_table "players", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "technique_abilities", force: :cascade do |t|
    t.bigint "ability_id", null: false
    t.datetime "created_at", null: false
    t.bigint "technique_id", null: false
    t.datetime "updated_at", null: false
    t.index ["ability_id"], name: "index_technique_abilities_on_ability_id"
    t.index ["technique_id", "ability_id"], name: "index_technique_abilities_on_technique_id_and_ability_id", unique: true
    t.index ["technique_id"], name: "index_technique_abilities_on_technique_id"
  end

  create_table "techniques", force: :cascade do |t|
    t.integer "attack_range", null: false
    t.bigint "card_id", null: false
    t.datetime "created_at", null: false
    t.integer "movement_count", null: false
    t.string "movement_type", null: false
    t.string "technique_type", null: false
    t.datetime "updated_at", null: false
    t.index ["card_id"], name: "index_techniques_on_card_id", unique: true
  end

  add_foreign_key "cards", "nations"
  add_foreign_key "game_players", "games"
  add_foreign_key "game_players", "players"
  add_foreign_key "technique_abilities", "abilities"
  add_foreign_key "technique_abilities", "techniques"
  add_foreign_key "techniques", "cards"
end
