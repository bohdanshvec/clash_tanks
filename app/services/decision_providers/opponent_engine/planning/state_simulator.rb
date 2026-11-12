
module DecisionProviders
  module OpponentEngine
    module Planning
      class StateSimulator
        Result = Data.define(
          :success?,
          :error,
          :visible_state,
          :events
        )

        def self.call(visible_state:, player_id:, action:, current_time:)
          new(
            visible_state:,
            player_id:,
            action:,
            current_time:
          ).call
        end

        def initialize(visible_state:, player_id:, action:, current_time:)
          @visible_state = visible_state
          @player_id = player_id.to_s
          @action_data = action
          @current_time = current_time
        end

        def call
          return failure("Game is not started") unless
            @visible_state["status"] == "started"

          return failure("Player does not exist") unless
            @visible_state.fetch("players").key?(@player_id)

          return failure("It is not the AI player's turn") unless
            @visible_state["current_player_id"].to_s == @player_id

          state = build_simulation_state
          action = build_engine_action

          result = GameEngine::Engine.new(
            state,
            current_time: @current_time
          ).call(action)

          return failure(result.error) unless result.success?

          simulated_visible_state = GameEngine::VisibleState.call(
            state: result.state,
            player_id: @player_id
          )

          # Во всей цепочке поиска используем одно фиксированное время.
          simulated_visible_state["server_time"] = @current_time.iso8601

          Result.new(
            success?: true,
            error: nil,
            visible_state: simulated_visible_state,
            events: result.events
          )
        end

        private

        def build_simulation_state
          {
            "status" => @visible_state["status"],
            "turn_number" => @visible_state["turn_number"],
            "current_player_id" => @visible_state["current_player_id"],
            "turn_started_at" => @visible_state["turn_started_at"],
            "field" => @visible_state.fetch("field").deep_dup,
            "players" => build_players,
            "result" => @visible_state["result"]&.deep_dup
          }
        end

        def build_players
          @visible_state.fetch("players").to_h do |player_id, visible_player|
            player_id = player_id.to_s
            is_ai_player = player_id == @player_id

            hand =
              if is_ai_player
                visible_player.fetch("hand").deep_dup
              else
                hidden_cards(
                  visible_player.fetch("hand_count"),
                  player_id,
                  "hand"
                )
              end

            deck = hidden_cards(
              visible_player.fetch("deck_count"),
              player_id,
              "deck"
            )

            graveyard = hidden_cards(
              visible_player.fetch("graveyard_count"),
              player_id,
              "graveyard"
            )

            [
              player_id,
              {
                "nation_id" => visible_player["nation_id"],
                "hand" => hand,
                "deck" => deck,
                "graveyard" => graveyard,
                "platoons" => visible_player.fetch("platoons").deep_dup,
                "resources" => visible_player["resources"],
                "remaining_time" => visible_player["remaining_time"],
                "empty_deck_draw_attempts" =>
                  visible_player["empty_deck_draw_attempts"]
              }
            ]
          end
        end

        def hidden_cards(count, player_id, zone)
          Array.new(count.to_i) do |index|
            {
              "card_id" => "hidden-#{player_id}-#{zone}-#{index}",
              "card_type" => "unknown"
            }
          end
        end

        def build_engine_action
          type = action_value(@action_data, "type")
          payload = action_value(@action_data, "payload") || {}

          GameEngine::Action.new(
            player_id: @visible_state["current_player_id"],
            type: type.to_s,
            payload: symbolize_keys(payload)
          )
        end

        def action_value(hash, key)
          return hash[key] if hash.key?(key)

          hash[key.to_sym]
        end

        def symbolize_keys(value)
          case value
          when Hash
            value.each_with_object({}) do |(key, item), result|
              result[key.to_sym] = symbolize_keys(item)
            end
          when Array
            value.map { |item| symbolize_keys(item) }
          else
            value
          end
        end

        def failure(error)
          Result.new(
            success?: false,
            error: error,
            visible_state: nil,
            events: []
          )
        end
      end
    end
  end
end
