module GameEngine
  module Actions
    class Attack
      def initialize(state, action)
        @state = state
        @action = action
      end

      def call
        return failure("Player does not exist") unless player_exists?
        return failure("It is not player's turn") unless current_player?

        attacker_position = @action.payload[:attacker]
        target_position = @action.payload[:target]

        return failure("Invalid coordinates") unless valid_coordinates?(attacker_position)
        return failure("Invalid coordinates") unless valid_coordinates?(target_position)

        attacker = object_at(attacker_position)
        target = object_at(target_position)

        return failure("Attacker cell is empty") unless attacker
        return failure("Target cell is empty") unless target
        return failure("Attacker does not belong to player") unless attacker["player_id"] == @action.player_id
        return failure("Target belongs to player") if target["player_id"] == @action.player_id

        case attacker["type"]
        when "technique"
          attack_technique(attacker, target, attacker_position, target_position)
        when "headquarters"
          attack_headquarters(attacker, target, attacker_position, target_position)
        else
          failure("Invalid attacker type")
        end
      end

      private

      def attack_technique(attacker, target, attacker_position, target_position)
        return failure("Target is not a technique") unless target["type"] == "technique"
        return failure("Technique has already attacked") if attacker["has_attacked"]
        return failure("Invalid attack range") unless valid_attack_range?(attacker, attacker_position, target_position)

        ptsau_first = ptsau_shoots_first?(attacker, target, attacker_position, target_position)

        new_state = @state.deep_dup

        new_attacker = new_state["field"][attacker_position[0]][attacker_position[1]]
        new_target = new_state["field"][target_position[0]][target_position[1]]

        new_attacker["has_attacked"] = true

        if ptsau_first
          new_attacker["hp"] -= new_target["firepower"]

          if new_attacker["hp"] <= 0
            new_state["field"][attacker_position[0]][attacker_position[1]] = nil

            return Result.new(
              success: true,
              state: new_state,
              events: [{ type: "technique_attacked" }]
            )
          end
        end

        new_target["hp"] -= new_attacker["firepower"]

        if new_target["hp"] <= 0
          new_state["field"][target_position[0]][target_position[1]] = nil
        elsif !ptsau_first
          counterattack(
            new_state,
            attacker_position,
            target_position
          )
        end

        Result.new(
          success: true,
          state: new_state,
          events: [{ type: "technique_attacked" }]
        )
      end

      def counterattack(state, attacker_position, target_position)
        attacker = state["field"][attacker_position[0]][attacker_position[1]]
        defender = state["field"][target_position[0]][target_position[1]]

        return unless attacker
        return unless defender
        return if defender["has_counterattacked"]

        row_delta = (target_position[0] - attacker_position[0]).abs
        column_delta = (target_position[1] - attacker_position[1]).abs

        return unless [row_delta, column_delta].max == 1

        defender["has_counterattacked"] = true
        attacker["hp"] -= defender["firepower"]

        if attacker["hp"] <= 0
          state["field"][attacker_position[0]][attacker_position[1]] = nil
        end
      end

      def attack_headquarters(attacker, target, attacker_position, target_position)
        return failure("Headquarters has already attacked") if attacker["has_attacked"]

        case target["type"]
        when "headquarters"
          attack_headquarters_target(
            attacker,
            target,
            attacker_position,
            target_position
          )
        when "technique"
          attack_technique_target_from_headquarters(
            attacker,
            target,
            attacker_position,
            target_position
          )
        else
          failure("Invalid target type")
        end
      end

      def attack_headquarters_target(attacker, target, attacker_position, target_position)
        new_state = @state.deep_dup

        new_attacker = new_state["field"][attacker_position[0]][attacker_position[1]]
        new_target = new_state["field"][target_position[0]][target_position[1]]

        new_attacker["has_attacked"] = true
        new_target["hp"] -= new_attacker["firepower"]

        if new_target["hp"] <= 0
          new_state["field"][target_position[0]][target_position[1]] = nil
        end

        Result.new(
          success: true,
          state: new_state,
          events: [{ type: "headquarters_attacked" }]
        )
      end

      def attack_technique_target_from_headquarters(attacker, target, attacker_position, target_position)
        unless technique_on_bridgehead?(target_position, attacker["player_id"]) ||
               allied_technique_near?(target_position, attacker["player_id"])
          return failure("Technique is out of headquarters attack range")
        end

        new_state = @state.deep_dup

        new_attacker = new_state["field"][attacker_position[0]][attacker_position[1]]
        new_target = new_state["field"][target_position[0]][target_position[1]]

        new_attacker["has_attacked"] = true
        new_target["hp"] -= new_attacker["firepower"]

        if new_target["hp"] <= 0
          new_state["field"][target_position[0]][target_position[1]] = nil
        end

        Result.new(
          success: true,
          state: new_state,
          events: [{ type: "headquarters_attacked" }]
        )
      end

      def ptsau_shoots_first?(attacker, target, attacker_position, target_position)
        return false unless target["technique_type"] == "tank_destroyer"
        return false unless %w[light_tank medium_tank heavy_tank].include?(attacker["technique_type"])

        row_delta = (target_position[0] - attacker_position[0]).abs
        column_delta = (target_position[1] - attacker_position[1]).abs

        [row_delta, column_delta].max == 1
      end

      def player_exists?
        @state["players"].key?(@action.player_id.to_s)
      end

      def current_player?
        @state["current_player_id"].to_s == @action.player_id.to_s
      end

      def allied_technique_near?(position, player_id)
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
              object["type"] == "technique" &&
              object["player_id"].to_s == player_id.to_s
          end
        end
      end

      def technique_on_bridgehead?(position, player_id)
        hq_position = nil

        @state["field"].each_with_index do |row, row_index|
          row.each_with_index do |object, column_index|
            next unless object
            next unless object["type"] == "headquarters"
            next unless object["player_id"].to_s == player_id.to_s

            hq_position = [row_index, column_index]
          end
        end

        return false unless hq_position

        row_delta = (position[0] - hq_position[0]).abs
        column_delta = (position[1] - hq_position[1]).abs

        row_delta <= 1 &&
          column_delta <= 1 &&
          (row_delta + column_delta).positive?
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

      def valid_attack_range?(attacker, from, to)
        row_delta = (to[0] - from[0]).abs
        column_delta = (to[1] - from[1]).abs

        distance = [row_delta, column_delta].max

        distance <= attacker["attack_range"]
      end

      def failure(error)
        Result.new(success: false, error: error)
      end
    end
  end
end

