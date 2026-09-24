module GameEngine
  class VisibleState
    def self.call(state:, player_id:)
      new(state, player_id).call
    end

    def initialize(state, player_id)
      @state = state
      @player_id = player_id.to_s
    end

    def call
      {
        "status" => @state["status"],
        "turn_number" => @state["turn_number"],
        "current_player_id" => @state["current_player_id"],
        "field" => @state["field"].deep_dup,
        "players" => visible_players
      }
    end

    private

    def visible_players
      @state.fetch("players").to_h do |player_id, player_state|
        if player_id.to_s == @player_id
          [player_id, visible_own_player(player_state)]
        else
          [player_id, visible_opponent_player(player_state)]
        end
      end
    end

    def visible_own_player(player_state)
      {
        "nation_id" => player_state["nation_id"],
        "hand" => player_state["hand"].deep_dup,
        "deck_count" => player_state["deck"].length,
        "platoons" => player_state["platoons"].deep_dup,
        "resources" => player_state["resources"],
        "remaining_time" => player_state["remaining_time"],
        "empty_deck_draw_attempts" => player_state["empty_deck_draw_attempts"]
      }
    end

		def visible_opponent_player(player_state)
			{
				"nation_id" => player_state["nation_id"],
				"hand_count" => player_state["hand"].length,
				"deck_count" => player_state["deck"].length,
				"remaining_time" => player_state["remaining_time"],
				"platoons" => player_state["platoons"].deep_dup
			}
		end
  end
end
