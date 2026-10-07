class AddGuestToPlayers < ActiveRecord::Migration[8.1]
  def change
    add_column :players, :guest, :boolean, null: false, default: false
    add_column :players, :last_seen_at, :datetime
  end
end
