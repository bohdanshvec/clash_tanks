class AddDeckToGamePlayers < ActiveRecord::Migration[8.1]
  def change
    add_reference :game_players, :deck, null: false, foreign_key: true
  end
end
