module GameEngine
  module Abilities
    class Executor
      HANDLERS = {
        "damage_technique" => DamageTechnique
      }.freeze

      def initialize(state:, ability:, player_id:, targets:)
        @state = state
        @ability = ability
        @player_id = player_id
        @targets = targets
      end

      def call
        handler_class = HANDLERS[@ability["code"]]

        return failure("Unknown ability") unless handler_class

        handler_class.new(
          state: @state,
          ability: @ability,
          player_id: @player_id,
          targets: @targets
        ).call
      end

      private

      def failure(error)
        Result.new(
          success: false,
          error: error
        )
      end
    end
  end
end
