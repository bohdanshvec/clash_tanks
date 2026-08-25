class CreateCards < ActiveRecord::Migration[8.1]
  def change
    create_table :cards do |t|
      t.references :nation, null: false, foreign_key: true
      t.string :name
      t.string :card_type
      t.integer :weight

      t.timestamps
    end
  end
end
