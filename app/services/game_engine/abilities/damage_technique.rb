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
        damage = @ability["damage"].to_i

        target["hp"] -= damage

        if target["hp"] <= 0
          destroy_technique(new_state, target, row, column)
        end

        Result.new(
          success: true,
          state: new_state,
          events: [{ type: "technique_damaged" }]
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
