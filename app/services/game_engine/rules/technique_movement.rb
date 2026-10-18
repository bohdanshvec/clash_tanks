module GameEngine
  module Rules
    class TechniqueMovement
      def self.valid?(technique, from, to)
        new(technique, from, to).valid?
      end

      def initialize(technique, from, to)
        @technique = technique
        @from = from
        @to = to
      end

      def valid?
        return false unless Position.adjacent?(@from, @to)

        row_delta = (@to[0] - @from[0]).abs
        column_delta = (@to[1] - @from[1]).abs

        case @technique["movement_type"]
        when "orthogonal"
          row_delta + column_delta == 1
        when "diagonal"
          true
        else
          false
        end
      end
    end
  end
end
