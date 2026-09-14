class CreatePlatoons < ActiveRecord::Migration[8.1]
  def change
    create_table :platoons do |t|
      t.references :card, null: false, foreign_key: true, index: { unique: true }
      t.integer :firepower, null: false
      t.integer :hp, null: false
      t.integer :armor, null: false
      t.integer :fuel, null: false

      t.timestamps
    end
  end
end
