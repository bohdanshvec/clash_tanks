module GameEngine
  module Rules
    class Counterattack
      def self.allowed?(
        attacker:,
        defender:,
        attacker_position:,
        defender_position:
      )
        new(
          attacker: attacker,
          defender: defender,
          attacker_position: attacker_position,
          defender_position: defender_position
        ).allowed?
      end

      def initialize(
        attacker:,
        defender:,
        attacker_position:,
        defender_position:
      )
        @attacker = attacker
        @defender = defender
        @attacker_position = attacker_position
        @defender_position = defender_position
      end

      def allowed?
        return false unless adjacent?
        return false if @defender["has_counterattacked"]

        true
      end

      private

      def adjacent?
        Position.adjacent?(
          @attacker_position,
          @defender_position
        )
      end
    end
  end
end
