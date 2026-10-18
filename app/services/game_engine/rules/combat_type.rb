module GameEngine
  module Rules
    class CombatType
      def self.call(attacker:, target:, attacker_position:, target_position:)
        new(
          attacker: attacker,
          target: target,
          attacker_position: attacker_position,
          target_position: target_position
        ).call
      end

      def initialize(attacker:, target:, attacker_position:, target_position:)
        @attacker = attacker
        @target = target
        @attacker_position = attacker_position
        @target_position = target_position
      end

      def call
        # Штаб против штаба никогда не вызывает контратаку.
        return :ranged if headquarters_vs_headquarters?

        # Любая атака не по соседней клетке считается дальней.
        return :ranged unless adjacent?

        # Защищающаяся ПТ-САУ может выстрелить первой.
        return :ptsau_first if ptsau_shoots_first?

        # Остальные атаки по соседним клеткам — обычные.
        :normal
      end

      private

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

      def ptsau_shoots_first?
        return false unless @target["type"] == "technique"
        return false unless @target["technique_type"] == "tank_destroyer"

        # ПТ-САУ может контратаковать только один раз за ход противника.
        return false if @target["has_counterattacked"]

        # В дуэли ПТ-САУ первой стреляет атакующая ПТ-САУ.
        return false if @attacker["technique_type"] == "tank_destroyer"

        true
      end
    end
  end
end
