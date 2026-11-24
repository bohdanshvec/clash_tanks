module GameEngine
  module Abilities
    class DamageTechnique
      def initialize(state:, ability:, player_id:, targets:)
        @state = state
        @ability = ability
        @player_id = player_id
        @targets = targets
      end

      def call
        return failure("Invalid target") unless valid_target?

        new_state = @state.deep_dup

        row, column = target_position
        target = new_state["field"][row][column]

        requested_damage = @ability["damage"].to_i
        hp_before = target["hp"]

        target["hp"] = [hp_before - requested_damage, 0].max
        hp_after = target["hp"]
        actual_damage = hp_before - hp_after

        target_data = object_data(target, [row, column])

        source = {
          type: "order",
          code: @ability["code"]
        }

        events = [
          {
            type: "damage_applied",
            source: source,
            target: target_data,
            damage: actual_damage,
            hp_before: hp_before,
            hp_after: hp_after
          }
        ]

        if hp_after.zero?
          destroy_technique(new_state, target, row, column)

          events << {
            type: "technique_destroyed",
            source: source,
            target: target_data
          }
        end

        Result.new(
          success: true,
          state: new_state,
          events: events
        )
      end

      private

      def valid_target?
        position = target_position

        return false unless position
        return false unless GameState.valid_coordinates?(
          row: position[0],
          column: position[1]
        )

        object = @state["field"][position[0]][position[1]]

        object &&
          object["type"] == "technique" &&
          object["player_id"].to_s != @player_id.to_s
      end

      def target_position
        return unless @targets.is_a?(Array)
        return unless @targets.size == 1

        target = @targets.first

        case target
        when Array
          return unless target.size == 2
          return unless target.all? { |coordinate| coordinate.is_a?(Integer) }

          target
        when Hash
          row = target[:row] || target["row"]
          column = target[:column] || target["column"]

          return unless row.is_a?(Integer)
          return unless column.is_a?(Integer)

          [row, column]
        end
      end

      def object_data(object, position)
        {
          type: object["type"],
          player_id: object["player_id"],
          card_id: object["card_id"],
          name: object["name"],
          position: position.dup
        }
      end

      def destroy_technique(state, technique, row, column)
        state["players"][
          technique["player_id"].to_s
        ]["graveyard"] << technique

        state["field"][row][column] = nil
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