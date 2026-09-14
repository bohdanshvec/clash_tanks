class CreateCardAbilities < ActiveRecord::Migration[8.1]
  def change
    create_table :card_abilities do |t|
      t.references :card, null: false, foreign_key: true
      t.references :ability, null: false, foreign_key: true
      t.jsonb :parameters, null: false, default: {}

      t.timestamps
    end

    add_index :card_abilities, [:card_id, :ability_id], unique: true
  end
end
