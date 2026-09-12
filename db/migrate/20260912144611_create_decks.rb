class CreateDecks < ActiveRecord::Migration[8.1]
  def change
    create_table :decks do |t|
      t.references :player, null: false, foreign_key: true
      t.references :nation, null: false, foreign_key: true
      t.string :name, null: false

      t.timestamps
    end
  end
end
