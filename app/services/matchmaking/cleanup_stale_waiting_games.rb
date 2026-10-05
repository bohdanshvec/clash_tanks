module Matchmaking
  class CleanupStaleWaitingGames
    STALE_AFTER = 30.seconds

    def self.call
      new.call
    end

    def call
      stale_games = Game
        .where(status: "waiting")
        .where("last_seen_at < ?", STALE_AFTER.ago)

      stale_games.find_each do |game|
        destroy_game(game)
      end
    end

    private

    def destroy_game(game)
      destroyed = false

      game.with_lock do
        next unless game.waiting?

        next unless game.last_seen_at
        next unless game.last_seen_at < STALE_AFTER.ago

        game.destroy!
        destroyed = true
      end

      broadcast_waiting_games_refresh if destroyed
    end

    def broadcast_waiting_games_refresh
      Game
        .where(status: "waiting")
        .find_each do |game|
          Turbo::StreamsChannel.broadcast_refresh_to(game)
        end
    end
  end
end
