module GameEngine
  module Actions
    class PlayCard
      def initialize(state, action)
        @state = state
        @action = action
      end

      def call
        return failure("Player does not exist") unless player_exists?
        return failure("It is not player's turn") unless current_player?

        card = card_from_hand
        return failure("Card is not in hand") unless card

        return failure("Card is not a technique") unless card["card_type"] == "technique"

        price = card["price"].to_i
        return failure("Not enough resources") if player_resources < price

        position = [
          @action.payload[:row],
          @action.payload[:column]
        ]

        return failure("Invalid coordinates") unless valid_coordinates?(position)
        return failure("Destination cell is occupied") if object_at(position)
        return failure("Technique must be placed adjacent to headquarters") unless adjacent_to_own_headquarters?(position)

        new_state = @state.deep_dup
        player = new_state["players"][@action.player_id.to_s]

        player["hand"].delete_at(
          player["hand"].index { |hand_card| hand_card["card_id"] == card["card_id"] }
        )
        player["resources"] -= price

        new_state["field"][position[0]][position[1]] = technique_object(card)

        Result.new(
          success: true,
          state: new_state,
          events: [{ type: "technique_played" }]
        )
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

      def player_resources
        player["resources"].to_i
      end

      def card_from_hand
        player["hand"].find do |card|
          card["card_id"].to_i == @action.payload[:card_id].to_i
        end
      end

      def valid_coordinates?(coordinates)
        coordinates.is_a?(Array) &&
          coordinates.length == 2 &&
          coordinates.all? { |coordinate| coordinate.is_a?(Integer) } &&
          GameState.valid_coordinates?(
            row: coordinates[0],
            column: coordinates[1]
          )
      end

      def object_at(coordinates)
        @state["field"][coordinates[0]][coordinates[1]]
      end

      def adjacent_to_own_headquarters?(position)
        row = position[0]
        column = position[1]

        (-1..1).any? do |row_offset|
          (-1..1).any? do |column_offset|
            next if row_offset.zero? && column_offset.zero?

            neighbor_row = row + row_offset
            neighbor_column = column + column_offset

            next unless GameState.valid_coordinates?(
              row: neighbor_row,
              column: neighbor_column
            )

            object = @state["field"][neighbor_row][neighbor_column]

            object &&
              object["type"] == "headquarters" &&
              object["player_id"].to_s == @action.player_id.to_s
          end
        end
      end

      def technique_object(card)
        technique = card["technique"]

        {
          "type" => "technique",
          "card_id" => card["card_id"],
          "player_id" => @action.player_id,
          "nation_id" => card["nation_id"],
          "name" => card["name"],
          "technique_type" => technique["technique_type"],
          "hp" => technique["hp"],
          "firepower" => technique["firepower"],
          "fuel" => technique["fuel"],
          "attack_range" => technique["attack_range"],
          "movement_count" => technique["movement_count"],
          "movement_type" => technique["movement_type"],
          "has_attacked" => false,
          "has_counterattacked" => false
        }
      end

      def failure(error)
        Result.new(success: false, error: error)
      end
    end
  end
end
