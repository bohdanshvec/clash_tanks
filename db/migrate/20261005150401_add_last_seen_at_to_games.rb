class AddLastSeenAtToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :last_seen_at, :datetime
    add_index :games, :last_seen_at
  end
end
