class AddStateToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :state, :jsonb
  end
end
