class MakeAiPlayerUnique < ActiveRecord::Migration[8.1]
  def change
    remove_index :players, :ai

    add_index :players,
              :ai,
              unique: true,
              where: "ai = TRUE",
              name: "index_players_on_single_ai"
  end
end
