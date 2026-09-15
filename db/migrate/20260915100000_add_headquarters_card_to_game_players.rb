class AddHeadquartersCardToGamePlayers < ActiveRecord::Migration[8.1]
  def change
    add_reference :game_players,
                  :headquarters_card,
                  null: false,
                  foreign_key: { to_table: :cards }
  end
end
