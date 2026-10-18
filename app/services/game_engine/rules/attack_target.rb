module GameEngine
  module Rules
    class AttackTarget
      def self.valid?(
        state:,
        attacker:,
        target:,
        attacker_position:,
        target_position:
      )
        new(
          state: state,
          attacker: attacker,
          target: target,
          attacker_position: attacker_position,
          target_position: target_position
        ).valid?
      end

      def initialize(
        state:,
        attacker:,
        target:,
        attacker_position:,
        target_position:
      )
        @state = state
        @attacker = attacker
        @target = target
        @attacker_position = attacker_position
        @target_position = target_position
      end

      def valid?
        return false unless valid_object_types?

        # Штаб может атаковать вражеский штаб на любом расстоянии.
        return true if headquarters_vs_headquarters?

        return true if adjacent?

        case @attacker["type"]
        when "headquarters"
          valid_headquarters_attack?
        when "technique"
          valid_technique_attack?
        else
          false
        end
      end

      private

      def valid_object_types?
        %w[technique headquarters].include?(@attacker["type"]) &&
          %w[technique headquarters].include?(@target["type"])
      end

      def headquarters_vs_headquarters?
        @attacker["type"] == "headquarters" &&
          @target["type"] == "headquarters"
      end

      def adjacent?
        Position.adjacent?(
          @attacker_position,
          @target_position
        )
      end

      def valid_headquarters_attack?
        # Дальняя атака штаба по технике требует разведки:
        # рядом с целью должна находиться союзная техника
        # или штаб атакующего игрока.
        @target["type"] == "technique" &&
          Spotting.allied_unit_near?(
            @state,
            @target_position,
            @attacker["player_id"]
          )
      end

      def valid_technique_attack?
        # Обычная техника атакует в пределах своей дальности.
        return true if AttackRange.valid?(
          @attacker,
          @attacker_position,
          @target_position
        )

        # САУ может атаковать цель на любом расстоянии,
        # если рядом с целью находится союзная техника
        # или штаб атакующего игрока.
        @attacker["technique_type"] == "artillery" &&
          Spotting.allied_unit_near?(
            @state,
            @target_position,
            @attacker["player_id"]
          )
      end
    end
  end
end
