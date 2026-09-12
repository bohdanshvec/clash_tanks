class AddStatsToTechniques < ActiveRecord::Migration[8.1]
  def change
    add_column :techniques, :firepower, :integer, null: false
    add_column :techniques, :hp, :integer, null: false
    add_column :techniques, :fuel, :integer, null: false
  end
end
