class MakeCardPriceOptional < ActiveRecord::Migration[8.1]
  def change
    change_column_null :cards, :price, true
  end
end
