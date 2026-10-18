module GameEngine
  module Attacks
    class CombatExecutor
      def self.call(state:, attacker_position:, target_position:, scenario:)
        new(
          state: state,
          attacker_position: attacker_position,
          target_position: target_position,
          scenario: scenario
        ).call
      end

      def initialize(state:, attacker_position:, target_position:, scenario:)
        @state = state
        @attacker_position = attacker_position
        @target_position = target_position
        @scenario = scenario
      end

      # Возвращает объекты атаки, включая ссылки на уничтоженные
      # объекты, чтобы Actions::Attack мог сформировать события.
      def call
        attacker = object_at(@attacker_position)
        target = object_at(@target_position)

        case @scenario
        when :ranged
          execute_ranged_combat(attacker, target)
        when :normal
          execute_normal_combat(attacker, target)
        when :ptsau_first
          execute_ptsau_first_combat(attacker, target)
        else
          raise ArgumentError, "Unknown combat scenario: #{@scenario.inspect}"
        end

        {
          attacker: attacker,
          target: target
        }
      end

      private

      # Дальний бой не вызывает контратаку.
      def execute_ranged_combat(attacker, target)
        perform_shot(
          attacker,
          target,
          @target_position
        )
      end

      # Обычный бой:
      # атакующий стреляет первым;
      # выживший защитник может ответить один раз за ход противника.
      def execute_normal_combat(attacker, target)
        perform_shot(
          attacker,
          target,
          @target_position
        )

        # Уничтоженный защитник не контратакует.
        return if target["hp"] <= 0

        counterattack
      end

      # Особый бой:
      # защищающаяся ПТ-САУ стреляет первой.
      # Если атакующий уничтожен, его выстрел не выполняется.
      #
      # Исключение для дуэли ПТ-САУ уже учитывается CombatType.
      def execute_ptsau_first_combat(attacker, target)
        counterattack

        return if attacker["hp"] <= 0

        perform_shot(
          attacker,
          target,
          @target_position
        )
      end

      # Общий механизм выстрела для атаки и контратаки.
      # Сам по себе выстрел не инициирует новую контратаку.
      def perform_shot(attacker, target, target_position)
        damage = firepower_for_shot(attacker)

        apply_shot_damage(
          target,
          damage,
          target_position
        )
      end

      def firepower_for_shot(attacker)
        if attacker["type"] == "headquarters"
          HeadquartersCombat.firepower_for_shot(
            state: @state,
            headquarters: attacker
          )
        else
          attacker["firepower"]
        end
      end

      def apply_shot_damage(target, damage, target_position)
        if target["type"] == "headquarters"
          HeadquartersCombat.apply_damage(
            state: @state,
            headquarters: target,
            damage: damage
          )
        else
          target["hp"] -= damage
          target["hp"] = 0 if target["hp"] < 0

          destroy_technique(target, target_position) if target["hp"] <= 0
        end
      end

      # Используется и для обычной контратаки, и для первого выстрела ПТ-САУ.
      def counterattack
        attacker = object_at(@attacker_position)
        defender = object_at(@target_position)

        return unless attacker
        return unless defender

        return unless Rules::Counterattack.allowed?(
          attacker: attacker,
          defender: defender,
          attacker_position: @attacker_position,
          defender_position: @target_position
        )

        # Флаг выставляется только при фактическом ответном выстреле.
        defender["has_counterattacked"] = true

        perform_shot(
          defender,
          attacker,
          @attacker_position
        )
      end

      def destroy_technique(technique, position)
        player = @state["players"][technique["player_id"].to_s]
        player["graveyard"] << technique.deep_dup

        @state["field"][position[0]][position[1]] = nil
      end

      def object_at(position)
        @state["field"][position[0]][position[1]]
      end
    end
  end
end
