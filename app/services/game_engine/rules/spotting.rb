module GameEngine
  module Rules
    class Spotting
      def self.allied_technique_near?(state, position, player_id)
        neighbor_objects(state, position).any? do |object|
          object &&
            object["type"] == "technique" &&
            object["player_id"].to_s == player_id.to_s
        end
      end

      def self.allied_unit_near?(state, position, player_id)
        neighbor_objects(state, position).any? do |object|
          object &&
            %w[technique headquarters].include?(object["type"]) &&
            object["player_id"].to_s == player_id.to_s
        end
      end

      def self.neighbor_objects(state, position)
        Position.neighbors(position).filter_map do |neighbor_position|
          state["field"][neighbor_position[0]][neighbor_position[1]]
        end
      end

      private_class_method :neighbor_objects
    end
  end
end

