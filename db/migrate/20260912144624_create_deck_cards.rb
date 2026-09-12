class CreateDeckCards < ActiveRecord::Migration[8.1]
  def change
    create_table :deck_cards do |t|
      t.references :deck, null: false, foreign_key: true
      t.references :card, null: false, foreign_key: true
      t.integer :quantity, null: false

      t.timestamps
    end

    add_index :deck_cards, [:deck_id, :card_id], unique: true
  end
end
