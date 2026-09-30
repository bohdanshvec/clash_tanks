module GameEngine
  module Actions
    class Surrender < Base
      def call
        return failure("Player does not exist") unless player_exists?

        opponent_id = @state["players"].keys.find do |player_id|
          player_id != @action.player_id.to_s
        end

        return failure("Opponent does not exist") unless opponent_id

        GameEngine::FinishGame.call(
          state: @state,
          winner_id: opponent_id,
          loser_id: @action.player_id,
          reason: "surrender"
        )
      end
    end
  end
end
