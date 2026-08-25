class AddUniqueIndexesToNationsAndAbilities < ActiveRecord::Migration[8.1]
  def change
    add_index :nations, :code, unique: true
    add_index :abilities, :code, unique: true
  end
end
