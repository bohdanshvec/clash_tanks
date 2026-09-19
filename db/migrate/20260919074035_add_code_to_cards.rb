class AddCodeToCards < ActiveRecord::Migration[8.1]
  def change
    add_column :cards, :code, :string
    add_index :cards, :code, unique: true
  end
end
