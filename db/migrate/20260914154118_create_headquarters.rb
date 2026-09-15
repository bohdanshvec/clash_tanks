class CreateHeadquarters < ActiveRecord::Migration[8.1]
  def change
		create_table :headquarters do |t|
			t.references :card, null: false, foreign_key: true
			t.integer :hp, null: false
			t.integer :firepower, null: false
			t.integer :fuel, null: false

			t.timestamps
		end
  end
end
