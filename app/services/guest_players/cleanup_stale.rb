module GuestPlayers
  class CleanupStale
    STALE_AFTER = 24.hours

    def self.call
      new.call
    end

    def call
      stale_guests.find_each do |player|
        destroy_guest(player)
      end
    end

    private

    def stale_guests
      Player
        .where(guest: true)
        .where("last_seen_at < ?", STALE_AFTER.ago)
    end

    def destroy_guest(player)
      player.with_lock do
        next unless player.guest?
        next unless player.last_seen_at
        next unless player.last_seen_at < STALE_AFTER.ago
        next if active_game_exists?(player)

        player.game_players
          .joins(:game)
          .where(games: { status: "finished" })
          .destroy_all

        player.destroy!
      end
    end

    def active_game_exists?(player)
      player.game_players
        .joins(:game)
        .where(games: { status: %w[waiting started] })
        .exists?
    end
  end
end
