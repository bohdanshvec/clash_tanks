module GameEngine
  class Engine
    ACTIONS = {
      "move" => Actions::Move,
      "attack" => Actions::Attack,
      "play_card" => Actions::PlayCard,
      "end_turn" => Actions::EndTurn
    }.freeze

    def initialize(state, current_time: Time.current)
      @state = state
      @current_time = current_time
    end

    def call(action)
      handler_class = ACTIONS[action.type]
      return failure("Unknown action type") unless handler_class
      return failure("Game is already finished") if @state["status"] == "finished"

			if current_player?(action)
				timer = GameEngine::TurnTimer.new(
					@state,
					current_time: @current_time
				)

				return finish_game_by_timeout(action) if timer.expired?
			end

      handler_class.new(@state, action).call
    end

    private

    def current_player?(action)
      @state["players"].key?(action.player_id.to_s) &&
        @state["current_player_id"].to_s == action.player_id.to_s
    end

    def failure(error)
      Result.new(success: false, error: error)
    end
    
		def finish_game_by_timeout(action)
			loser_id = action.player_id.to_s

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
