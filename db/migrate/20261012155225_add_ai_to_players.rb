class AddAiToPlayers < ActiveRecord::Migration[8.1]
  def change
    add_column :players, :ai, :boolean, null: false, default: false
    add_index :players, :ai
  end
end
