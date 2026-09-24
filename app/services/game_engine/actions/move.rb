module GameEngine
  module Actions
    class Move < Base

      def call
        return failure("Player does not exist") unless player_exists?
        return failure("It is not player's turn") unless current_player?

        from = @action.payload[:from]
        to = @action.payload[:to]

        return failure("Invalid coordinates") unless valid_coordinates?(from) && valid_coordinates?(to)

        technique = object_at(from)
        return failure("Source cell does not contain a technique") unless technique
        return failure("Source cell does not contain a technique") unless technique["type"] == "technique"
        return failure("Technique does not belong to player") unless technique["player_id"] == @action.player_id

        return failure("No movement remaining") unless technique["movement_count"].to_i > 0
        return failure("Destination cell is occupied") if object_at(to)
        return failure("Invalid movement") unless valid_movement?(technique, from, to)

        new_state = @state.deep_dup
        field = new_state["field"]

        moved_technique = field[from[0]][from[1]].dup
        moved_technique["movement_count"] -= 1

        field[from[0]][from[1]] = nil
        field[to[0]][to[1]] = moved_technique

        Result.new(
          success: true,
          state: new_state,
          events: [{ type: "technique_moved" }]
        )
      end

      private

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

      def valid_movement?(technique, from, to)
        row_delta = (to[0] - from[0]).abs
        column_delta = (to[1] - from[1]).abs

        return false if row_delta > 1 || column_delta > 1
        return false if row_delta.zero? && column_delta.zero?

        case technique["movement_type"]
        when "orthogonal"
          row_delta + column_delta == 1
        when "diagonal"
          true
        else
          false
        end
      end
    end
  end
end
