class AddNationToGamePlayers < ActiveRecord::Migration[8.1]
  def change
    add_reference :game_players, :nation, foreign_key: true
  end
end
