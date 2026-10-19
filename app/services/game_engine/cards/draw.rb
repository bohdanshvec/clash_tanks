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
        	break if new_state["status"] == "finished"
        
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
        hp_before = headquarters["hp"]
        headquarters["hp"] = [hp_before - damage, 0].max

        # Причина урона: попытка добрать карту из пустой колоды.
        events << {
          type: "empty_deck_draw_attempt",
          player_id: @player_id,
          damage: damage
        }

        # Универсальное событие нанесения урона.
        events << {
          type: "damage_applied",
          source: {
            type: "empty_deck_draw"
          },
          target: headquarters_data(state, headquarters),
          damage: hp_before - headquarters["hp"],
          hp_before: hp_before,
          hp_after: headquarters["hp"]
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

      def headquarters_data(state, headquarters)
        position = nil

        state["field"].each_with_index do |row, row_index|
          column_index = row.index do |object|
            object.equal?(headquarters)
          end

          next unless column_index

          position = [row_index, column_index]
          break
        end

        {
          type: "headquarters",
          player_id: headquarters["player_id"],
          card_id: headquarters["card_id"],
          name: headquarters["name"],
          position: position
        }
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
