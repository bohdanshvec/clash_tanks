class AddPriceToCards < ActiveRecord::Migration[8.1]
  def change
    add_column :cards, :price, :integer, null: false
  end
end
