class CreateTechniqueAbilities < ActiveRecord::Migration[8.1]
  def change
    create_table :technique_abilities do |t|
      t.references :technique, null: false, foreign_key: true
      t.references :ability, null: false, foreign_key: true

      t.timestamps
    end
    
    add_index :technique_abilities, [:technique_id, :ability_id], unique: true
  end
end
