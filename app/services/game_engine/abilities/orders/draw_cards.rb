
module GameEngine
  module Abilities
    module Orders
      class DrawCards
        CODE = "draw_cards"

        def self.description(parameters)
          count = parameters.to_h["count"]
          "Добрати карт: #{count}" if count.present?
        end

        def initialize(state:, ability:, player_id:, targets:)
          @state = state
          @ability = ability
          @player_id = player_id
          @targets = targets
        end

        def call
          return failure("Invalid draw count") unless valid_count?

          GameEngine::Cards::Draw.call(
            state: @state,
            player_id: @player_id,
            count: @ability["count"]
          )
        end

        private

        def valid_count?
          @ability["count"].is_a?(Integer) &&
            @ability["count"].positive?
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
end
