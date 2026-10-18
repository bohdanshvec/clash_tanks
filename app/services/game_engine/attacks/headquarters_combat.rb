module GameEngine
  module Attacks
    class HeadquartersCombat
      def self.firepower_for_shot(state:, headquarters:)
        new(state).firepower_for_shot(headquarters)
      end

      def self.apply_damage(state:, headquarters:, damage:)
        new(state).apply_damage(headquarters, damage)
      end

      def initialize(state)
        @state = state
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
      def apply_damage(headquarters, damage)
        return if damage <= 0

        player = player_for(headquarters)
        platoons = player["platoons"] || []
        remaining_damage = damage

        platoons.each_with_index do |platoon, index|
          next unless platoon

          armor = platoon["armor"].to_i
          absorbed_damage = [remaining_damage, armor].min

          platoon["hp"] -= absorbed_damage
          platoon["hp"] = 0 if platoon["hp"] < 0

          remaining_damage -= absorbed_damage

          next unless platoon["hp"] <= 0

          move_to_graveyard(player, platoon)
          player["platoons"][index] = nil

          break if remaining_damage <= 0
        end

        headquarters["hp"] -= remaining_damage
        headquarters["hp"] = 0 if headquarters["hp"] < 0
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

          platoon["hp"] -= platoon["firepower"]
          platoon["hp"] = 0 if platoon["hp"] < 0

          next unless platoon["hp"] <= 0

          move_to_graveyard(player, platoon)
          player["platoons"][index] = nil
        end
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
