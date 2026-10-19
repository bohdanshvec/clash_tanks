module GameEngine
  module Attacks
    class HeadquartersCombat
      def self.firepower_for_shot(state:, headquarters:, events: nil)
        new(state, events: events).firepower_for_shot(headquarters)
      end

      def self.apply_damage(state:, headquarters:, damage:, events: nil)
        new(state, events: events).apply_damage(headquarters, damage)
      end

      def initialize(state, events: nil)
        @state = state
        @events = events
      end

      # Штаб наносит урон, равный собственной огневой мощи
      # плюс огневая мощь всех действующих взводов.
      #
      # После выстрела каждый взвод теряет прочность,
      # равную собственной огневой мощи.
      def firepower_for_shot(headquarters)
        total_firepower = headquarters_total_firepower(headquarters)

        damage_platoons_after_attack(headquarters)

        total_firepower
      end

      # Входящий урон сначала поглощается бронёй взводов
      # в порядке слотов 0 -> 1 -> 2 -> 3.
      # Оставшийся урон получает штаб.
      #
      # Возвращает сведения о распределении урона.
      def apply_damage(headquarters, damage)
        hp_before = headquarters["hp"]

        if damage <= 0
          return {
            incoming_damage: damage,
            armor_absorbed: 0,
            headquarters_damage: 0,
            headquarters_hp_before: hp_before,
            headquarters_hp_after: hp_before
          }
        end

        player = player_for(headquarters)
        platoons = player["platoons"] || []
        remaining_damage = damage
        armor_absorbed = 0

        platoons.each_with_index do |platoon, index|
          next unless platoon
          break if remaining_damage <= 0

          armor = platoon["armor"].to_i
          absorbed_damage = [remaining_damage, armor].min
          next if absorbed_damage <= 0

          platoon_hp_before = platoon["hp"]

          platoon["hp"] -= absorbed_damage
          platoon["hp"] = 0 if platoon["hp"] < 0

          remaining_damage -= absorbed_damage
          armor_absorbed += absorbed_damage

          emit_platoon_damage(
            platoon,
            index,
            absorbed_damage,
            platoon_hp_before,
            platoon["hp"],
            "headquarters_defense"
          )

          next unless platoon["hp"] <= 0

          emit_platoon_destroyed(platoon, index, "headquarters_defense")

          move_to_graveyard(player, platoon)
          player["platoons"][index] = nil
        end

        headquarters["hp"] -= remaining_damage
        headquarters["hp"] = 0 if headquarters["hp"] < 0

        {
          incoming_damage: damage,
          armor_absorbed: armor_absorbed,
          headquarters_damage: remaining_damage,
          headquarters_hp_before: hp_before,
          headquarters_hp_after: headquarters["hp"]
        }
      end

      private

      def headquarters_total_firepower(headquarters)
        player = player_for(headquarters)
        platoons = player["platoons"] || []

        headquarters["firepower"] +
          platoons.compact.sum { |platoon| platoon["firepower"] }
      end

      def damage_platoons_after_attack(headquarters)
        player = player_for(headquarters)
        platoons = player["platoons"] || []

        platoons.each_with_index do |platoon, index|
          next unless platoon

          hp_before = platoon["hp"]
          damage = platoon["firepower"]

          platoon["hp"] -= damage
          platoon["hp"] = 0 if platoon["hp"] < 0

          emit_platoon_damage(
            platoon,
            index,
            damage,
            hp_before,
            platoon["hp"],
            "headquarters_attack"
          )

          next unless platoon["hp"] <= 0

          emit_platoon_destroyed(platoon, index, "headquarters_attack")

          move_to_graveyard(player, platoon)
          player["platoons"][index] = nil
        end
      end

      def emit_platoon_damage(platoon, slot, damage, hp_before, hp_after, source)
        return unless @events
        return if damage <= 0

        @events << {
          type: "platoon_damaged",
          platoon: platoon_data(platoon, slot),
          damage: damage,
          hp_before: hp_before,
          hp_after: hp_after,
          source: source
        }
      end

      def emit_platoon_destroyed(platoon, slot, source)
        return unless @events

        @events << {
          type: "platoon_destroyed",
          platoon: platoon_data(platoon, slot),
          source: source
        }
      end

      def platoon_data(platoon, slot)
        {
          type: platoon["type"],
          player_id: platoon["player_id"],
          card_id: platoon["card_id"],
          name: platoon["name"],
          slot: slot
        }
      end

      def player_for(headquarters)
        @state["players"][headquarters["player_id"].to_s]
      end

      def move_to_graveyard(player, object)
        player["graveyard"] << object.deep_dup
      end
    end
  end
end
