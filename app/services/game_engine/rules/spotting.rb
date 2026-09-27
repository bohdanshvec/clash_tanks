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
        row = position[0]
        column = position[1]

        (-1..1).flat_map do |row_offset|
          (-1..1).filter_map do |column_offset|
            next if row_offset.zero? && column_offset.zero?

            neighbor_row = row + row_offset
            neighbor_column = column + column_offset

            next unless GameState.valid_coordinates?(
              row: neighbor_row,
              column: neighbor_column
            )

            state["field"][neighbor_row][neighbor_column]
          end
        end
      end

      private_class_method :neighbor_objects
    end
  end
end
