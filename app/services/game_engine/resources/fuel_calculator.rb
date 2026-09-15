module GameEngine
  module Resources
    class FuelCalculator
      def self.call(state:, player_id:)
        new(state:, player_id:).call
      end

      def initialize(state:, player_id:)
        @state = state
        @player_id = player_id.to_s
      end

      def call
        headquarters_fuel + techniques_fuel + platoons_fuel
      end

      private

      def headquarters_fuel
        field_objects
          .find { |object| object["type"] == "headquarters" && object["player_id"].to_s == @player_id }
          &.fetch("fuel", 0) || 0
      end

      def techniques_fuel
        field_objects.sum do |object|
          next 0 unless object["type"] == "technique"
          next 0 unless object["player_id"].to_s == @player_id

          object.fetch("fuel", 0)
        end
      end

      def platoons_fuel
        player.fetch("platoons", []).compact.sum do |platoon|
          platoon.fetch("fuel", 0)
        end
      end

      def field_objects
        @state.fetch("field").flatten.compact
      end

      def player
        @state.fetch("players").fetch(@player_id)
      end
    end
  end
end
