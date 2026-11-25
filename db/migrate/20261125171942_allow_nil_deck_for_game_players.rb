class AllowNilDeckForGamePlayers < ActiveRecord::Migration[8.1]
  def change
    change_column_null :game_players, :deck_id, true
  end
end
