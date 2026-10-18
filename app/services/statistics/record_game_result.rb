module Statistics
  class RecordGameResult
    def self.call(game:)
      new(game: game).call
    end

    def initialize(game:)
      @game = game
    end

    def call
      return unless @game.pvp?
      return unless @game.finished?

      state = @game.state
      return unless state.is_a?(Hash)

      result = state["result"]
      return unless result.is_a?(Hash)

      winner_id = result["winner_id"]&.to_s
      loser_id = result["loser_id"]&.to_s

      return if winner_id.blank? || loser_id.blank?
      return if winner_id == loser_id

      participant_ids = state.fetch("players").keys.map(&:to_s)

      unless participant_ids.size == 2 &&
             participant_ids.include?(winner_id) &&
             participant_ids.include?(loser_id)
        raise ArgumentError, "Invalid game result participants"
      end

      recorded_participant_ids =
        @game.game_players.pluck(:player_id).map(&:to_s)

      unless recorded_participant_ids.sort == participant_ids.sort
        raise ArgumentError, "Game participants do not match game state"
      end

      Player.registered_humans
        .where(id: winner_id)
        .update_all(
          "battles_count = battles_count + 1, " \
          "wins_count = wins_count + 1"
        )

      Player.registered_humans
        .where(id: loser_id)
        .update_all(
          "battles_count = battles_count + 1, " \
          "losses_count = losses_count + 1"
        )
    end
  end
end
