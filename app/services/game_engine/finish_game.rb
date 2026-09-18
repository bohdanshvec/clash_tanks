module GameEngine
  class FinishGame
    VALID_REASONS = %w[
      headquarters_destroyed
      time_expired
      empty_deck_damage
    ].freeze

    def self.call(state:, winner_id:, loser_id:, reason:)
      new(
        state: state,
        winner_id: winner_id,
        loser_id: loser_id,
        reason: reason
      ).call
    end

    def initialize(state:, winner_id:, loser_id:, reason:)
      @state = state
      @winner_id = winner_id
      @loser_id = loser_id
      @reason = reason
    end

    def call
      return failure("Game is already finished") if finished?
      return failure("Winner does not exist") unless player_exists?(@winner_id)
      return failure("Loser does not exist") unless player_exists?(@loser_id)
      return failure("Winner and loser must be different") if same_player?
      return failure("Invalid finish reason") unless valid_reason?

      new_state = @state.deep_dup

      new_state["status"] = "finished"
      new_state["result"] = {
        "winner_id" => @winner_id,
        "loser_id" => @loser_id,
        "reason" => @reason
      }

      Result.new(
        success: true,
        state: new_state,
        events: [
          {
            type: "game_finished",
            winner_id: @winner_id,
            loser_id: @loser_id,
            reason: @reason
          }
        ]
      )
    end

    private

    def finished?
      @state["status"] == "finished"
    end

    def player_exists?(player_id)
      @state["players"].key?(player_id.to_s)
    end

    def same_player?
      @winner_id.to_s == @loser_id.to_s
    end

    def valid_reason?
      VALID_REASONS.include?(@reason)
    end

    def failure(error)
      Result.new(
        success: false,
        error: error
      )
    end
  end
end
