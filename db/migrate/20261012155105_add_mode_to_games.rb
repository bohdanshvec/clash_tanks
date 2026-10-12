class AddModeToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :mode, :string, null: false, default: "pvp"
    add_index :games, :mode
  end
end
