module GameEngine
  module Actions
    class Base
      def initialize(state, action)
        @state = state
        @action = action
      end

      private

      def player_exists?
        @state["players"].key?(@action.player_id.to_s)
      end

      def current_player?
        @state["current_player_id"].to_s == @action.player_id.to_s
      end

      def player
        @state["players"][@action.player_id.to_s]
      end

      def failure(error)
        Result.new(success: false, error: error)
      end
    end
  end
end
