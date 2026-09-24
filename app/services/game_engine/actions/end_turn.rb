module GameEngine
  module Actions
    class EndTurn < Base
			def initialize(state, action, current_time: Time.current)
				super(state, action)
				@current_time = current_time
			end

      def call
        return failure("Player does not exist") unless player_exists?
        return failure("It is not player's turn") unless current_player?

        timer = GameEngine::TurnTimer.new(
          @state,
          current_time: @current_time
        )

        return finish_game_by_timeout if timer.expired?

        new_state = @state.deep_dup
        current_player = new_state["players"][@action.player_id.to_s]

        current_player["remaining_time"] = timer.remaining_time_after_elapsed

        new_state["turn_number"] += 1
        new_state["current_player_id"] = next_player_id
        new_state["turn_started_at"] = @current_time.change(usec: 0).iso8601

        new_state = GameEngine::Turns::PreparePlayer.call(
          state: new_state,
          player_id: new_state["current_player_id"]
        )

        Result.new(
          success: true,
          state: new_state,
          events: [
            { type: "turn_ended" }
          ]
        )
      end

      private

      def next_player_id
        player_ids = @state["players"].keys
        next_player = player_ids.find do |player_id|
          player_id != @action.player_id.to_s
        end

        next_player.to_i
      end
      
			def finish_game_by_timeout
				loser_id = @action.player_id.to_s

				winner_id = @state["players"].keys.find do |player_id|
					player_id != loser_id
				end

				return failure("Opponent does not exist") unless winner_id

				GameEngine::FinishGame.call(
					state: @state,
					winner_id: winner_id,
					loser_id: loser_id,
					reason: "time_expired"
				)
			end
    end
  end
end
