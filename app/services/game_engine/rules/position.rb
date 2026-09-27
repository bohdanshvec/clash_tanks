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
    end
  end
end
