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
        @events = []
      end

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
          target: target,
          events: @events
        }
      end

      private

      def execute_ranged_combat(attacker, target)
        perform_shot(
          attacker,
          target,
          @attacker_position,
          @target_position
        )
      end

      def execute_normal_combat(attacker, target)
        perform_shot(
          attacker,
          target,
          @attacker_position,
          @target_position
        )

        return if target["hp"] <= 0

        counterattack
      end

      def execute_ptsau_first_combat(attacker, target)
        counterattack

        return if attacker["hp"] <= 0

        perform_shot(
          attacker,
          target,
          @attacker_position,
          @target_position
        )
      end

      def perform_shot(
        attacker,
        target,
        attacker_position,
        target_position,
        counterattack: false
      )
        source_data = object_data(attacker, attacker_position)
        target_data = object_data(target, target_position)

        @events << {
          type: counterattack ? "counterattack_fired" : "shot_fired",
          attacker: source_data,
          target: target_data
        }

        damage = firepower_for_shot(attacker)

        hp_before = target["hp"]

        apply_shot_damage(
          target,
          damage,
          target_position
        )

        @events << {
          type: "damage_applied",
          source: {
            type: counterattack ? "counterattack" : "shot",
            attacker: source_data
          },
          target: target_data,
          damage: hp_before - target["hp"],
          hp_before: hp_before,
          hp_after: target["hp"]
        }

        if target["type"] == "technique" && target["hp"] <= 0
          @events << {
            type: "technique_destroyed",
            target: object_data(target, target_position)
          }
        end
      end

      def firepower_for_shot(attacker)
        if attacker["type"] == "headquarters"
          HeadquartersCombat.firepower_for_shot(
            state: @state,
            headquarters: attacker,
            events: @events
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
            damage: damage,
            events: @events
          )
        else
          target["hp"] -= damage
          target["hp"] = 0 if target["hp"] < 0

          destroy_technique(target, target_position) if target["hp"] <= 0
        end
      end

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

        defender["has_counterattacked"] = true

        perform_shot(
          defender,
          attacker,
          @target_position,
          @attacker_position,
          counterattack: true
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

      def object_data(object, position)
        {
          type: object["type"],
          player_id: object["player_id"],
          card_id: object["card_id"],
          name: object["name"],
          position: position.dup
        }
      end
    end
  end
end

