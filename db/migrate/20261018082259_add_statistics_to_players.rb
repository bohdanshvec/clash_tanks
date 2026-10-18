class AddStatisticsToPlayers < ActiveRecord::Migration[8.1]
  def change
    add_column :players, :battles_count, :integer,
               default: 0, null: false

    add_column :players, :wins_count, :integer,
               default: 0, null: false

    add_column :players, :losses_count, :integer,
               default: 0, null: false

    add_check_constraint :players,
                         "battles_count >= 0",
                         name: "players_battles_count_nonnegative"

    add_check_constraint :players,
                         "wins_count >= 0",
                         name: "players_wins_count_nonnegative"

    add_check_constraint :players,
                         "losses_count >= 0",
                         name: "players_losses_count_nonnegative"
  end
end
