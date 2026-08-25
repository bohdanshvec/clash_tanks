module GameEngine
  module Actions
    class EndTurn
      def initialize(state, action)
        @state = state
        @action = action
      end

      def call
        return failure("Player does not exist") unless player_exists?
        return failure("It is not player's turn") unless current_player?

        new_state = @state.deep_dup
        new_state["turn_number"] += 1
        new_state["current_player_id"] = next_player_id

        Result.new(
          success: true,
          state: new_state,
          events: [
            { type: "turn_ended" }
          ]
        )
      end

      private

      def player_exists?
        @state["players"].key?(@action.player_id.to_s)
      end

      def current_player?
        @state["current_player_id"].to_s == @action.player_id.to_s
      end

      def next_player_id
        player_ids = @state["players"].keys

        next_player = player_ids.find do |player_id|
          player_id != @action.player_id.to_s
        end

        next_player.to_i
      end

      def failure(error)
        Result.new(
          success: false,
          error: error
        )
      end
    end
  end
end
