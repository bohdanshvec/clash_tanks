class RemoveTechniqueAbilities < ActiveRecord::Migration[8.1]
  def change
    drop_table :technique_abilities
  end
end
