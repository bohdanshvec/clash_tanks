module GameEngine
  module Turns
    class PreparePlayer
      def self.call(state:, player_id:)
        new(state:, player_id:).call
      end

      def initialize(state:, player_id:)
        @state = state
        @player_id = player_id.to_s
      end

      def call
        new_state = @state.deep_dup

        reset_techniques(new_state)
        reset_headquarters(new_state)

        new_state["players"][@player_id]["resources"] =
          GameEngine::Resources::FuelCalculator.call(
            state: new_state,
            player_id: @player_id
          )

        draw_result = GameEngine::Cards::Draw.call(
          state: new_state,
          player_id: @player_id,
          count: 1
        )

        raise draw_result.error unless draw_result.success?

        draw_result.state
      end

      private

      def reset_techniques(state)
        state["field"].each do |row|
          row.each do |object|
            next unless object
            next unless object["type"] == "technique"
            next unless object["player_id"].to_s == @player_id

            object["movement_count"] = object["movement_limit"]
            object["has_attacked"] = false
            object["has_counterattacked"] = false
          end
        end
      end

      def reset_headquarters(state)
        headquarters = state["field"].flatten.find do |object|
          object &&
            object["type"] == "headquarters" &&
            object["player_id"].to_s == @player_id
        end

        return unless headquarters

        headquarters["has_attacked"] = false
        headquarters["has_counterattacked"] = false
      end
    end
  end
end
