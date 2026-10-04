class AddHeadquartersCardToDecks < ActiveRecord::Migration[8.1]
  def change
    add_reference :decks,
                  :headquarters_card,
                  null: false,
                  foreign_key: { to_table: :cards }
  end
end
