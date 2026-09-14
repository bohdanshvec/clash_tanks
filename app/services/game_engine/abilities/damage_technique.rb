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

        target = new_state["field"][@targets.first[:row]][@targets.first[:column]]
        damage = @ability["damage"].to_i

        target["hp"] -= damage

        if target["hp"] <= 0
          destroy_technique(new_state, target)
        end

        Result.new(
          success: true,
          state: new_state,
          events: [{ type: "technique_damaged" }]
        )
      end

      private

      def valid_target?
        return false unless @targets.is_a?(Array)
        return false unless @targets.size == 1

        target = @targets.first

        return false unless target.is_a?(Hash)
        return false unless target[:row].is_a?(Integer)
        return false unless target[:column].is_a?(Integer)

        return false unless GameState.valid_coordinates?(
          row: target[:row],
          column: target[:column]
        )

        object = @state["field"][target[:row]][target[:column]]

        object &&
          object["type"] == "technique" &&
          object["player_id"].to_s != @player_id.to_s
      end

      def destroy_technique(state, technique)
        row = @targets.first[:row]
        column = @targets.first[:column]

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
