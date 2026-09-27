module GameEngine
  module Rules
    class AttackRange
      def self.valid?(attacker, from, to)
        row_delta = (to[0] - from[0]).abs
        column_delta = (to[1] - from[1]).abs

        distance = [row_delta, column_delta].max

        distance <= attacker["attack_range"]
      end
    end
  end
end
