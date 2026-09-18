module GameEngine
  module Cards
    class Draw
      def self.call(state:, player_id:, count:)
        new(state:, player_id:, count:).call
      end

      def initialize(state:, player_id:, count:)
        @state = state
        @player_id = player_id.to_s
        @count = count
      end

      def call
        return failure("Invalid draw count") unless valid_count?
        return failure("Player does not exist") unless player_exists?

        new_state = @state.deep_dup
        events = []

        @count.times do
          draw_one(new_state, events)
        end

        Result.new(
          success: true,
          state: new_state,
          events: events
        )
      end

      private

      def valid_count?
        @count.is_a?(Integer) && @count.positive?
      end

      def player_exists?
        @state["players"].key?(@player_id)
      end

      def draw_one(state, events)
        player = state["players"][@player_id]

        if player["deck"].empty?
          apply_empty_deck_damage(state, player, events)
          return
        end

        card = player["deck"].shift
        player["hand"] << card

        events << {
          type: "card_drawn",
          player_id: @player_id
        }
      end

			def apply_empty_deck_damage(state, player, events)
				player["empty_deck_draw_attempts"] += 1
				damage = player["empty_deck_draw_attempts"]

				headquarters = headquarters_for(state)
				headquarters["hp"] = [headquarters["hp"] - damage, 0].max

				events << {
					type: "empty_deck_draw_attempt",
					player_id: @player_id,
					damage: damage
				}

				return unless headquarters["hp"] <= 0

				opponent_id = opponent_id_for(state)

				finish_result = GameEngine::FinishGame.call(
					state: state,
					winner_id: opponent_id,
					loser_id: @player_id,
					reason: "empty_deck_damage"
				)

				raise finish_result.error unless finish_result.success?

				state.replace(finish_result.state)

				events.concat(finish_result.events)
			end

      def headquarters_for(state)
        headquarters = state["field"].flatten.find do |object|
          object &&
            object["type"] == "headquarters" &&
            object["player_id"].to_s == @player_id
        end

        raise "Player headquarters not found" unless headquarters

        headquarters
      end
      
			def opponent_id_for(state)
				state.fetch("players").keys.find do |player_id|
					player_id != @player_id
				end || raise("Opponent not found")
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
