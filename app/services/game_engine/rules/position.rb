module GameEngine
  module Rules
    class Position
      def self.adjacent?(first_position, second_position)
        row_delta = (
          first_position[0] - second_position[0]
        ).abs

        column_delta = (
          first_position[1] - second_position[1]
        ).abs

        [row_delta, column_delta].max == 1
      end

      def self.neighbors(position)
        row, column = position

        (-1..1).flat_map do |row_offset|
          (-1..1).filter_map do |column_offset|
            next if row_offset.zero? && column_offset.zero?

            neighbor = [
              row + row_offset,
              column + column_offset
            ]

            next unless GameState.valid_coordinates?(
              row: neighbor[0],
              column: neighbor[1]
            )

            neighbor
          end
        end
      end
    end
  end
end

