
module GameEngine
  module Attacks
    class HeadquartersCombat
      HEADQUARTERS_DEFENDER_ABILITY = "headquarters_defender"

      def self.firepower_for_shot(state:, headquarters:, events: nil)
        new(state, events: events).firepower_for_shot(headquarters)
      end

      def self.apply_damage(
        state:,
        headquarters:,
        damage:,
        events: nil,
        source: "headquarters_defense"
      )
        new(state, events: events).apply_damage(
          headquarters,
          damage,
          source: source
        )
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

      # Входящий урон сначала поглощается техникой-защитниками,
      # затем бронёй взводов, после чего штабом.
      def apply_damage(
        headquarters,
        damage,
        source: "headquarters_defense"
      )
        hp_before = headquarters["hp"]

        if damage <= 0
          return {
            incoming_damage: damage,
            technique_absorbed: 0,
            armor_absorbed: 0,
            headquarters_damage: 0,
            headquarters_hp_before: hp_before,
            headquarters_hp_after: hp_before
          }
        end

        player = player_for(headquarters)
        remaining_damage = damage
        technique_absorbed = 0
        armor_absorbed = 0

        # Сначала урон принимают техники, защищающие этот штаб.
        headquarters_defenders(headquarters).each do |defender|
          break if remaining_damage <= 0

          technique = defender[:technique]
          absorbed_damage = [
            remaining_damage,
            technique["hp"].to_i
          ].min

          next if absorbed_damage <= 0

          technique_hp_before = technique["hp"].to_i
          technique["hp"] = technique_hp_before - absorbed_damage

          remaining_damage -= absorbed_damage
          technique_absorbed += absorbed_damage

          emit_technique_damage(
            technique,
            defender[:row],
            defender[:column],
            absorbed_damage,
            technique_hp_before,
            technique["hp"],
            source
          )

          next unless technique["hp"] <= 0

          emit_technique_destroyed(
            technique,
            defender[:row],
            defender[:column],
            source
          )

          move_to_graveyard(player, technique)
          @state["field"][defender[:row]][defender[:column]] = nil
        end

        # Затем урон поглощается бронёй взводов.
        platoons = player["platoons"] || []

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
            source
          )

          next unless platoon["hp"] <= 0

          emit_platoon_destroyed(platoon, index, source)

          move_to_graveyard(player, platoon)
          player["platoons"][index] = nil
        end

        # Остаток урона получает штаб.
        headquarters["hp"] -= remaining_damage
        headquarters["hp"] = 0 if headquarters["hp"] < 0

        {
          incoming_damage: damage,
          technique_absorbed: technique_absorbed,
          armor_absorbed: armor_absorbed,
          headquarters_damage: remaining_damage,
          headquarters_hp_before: hp_before,
          headquarters_hp_after: headquarters["hp"]
        }
      end

      private

      def headquarters_defenders(headquarters)
        headquarters_position = headquarters_position(headquarters)
        return [] unless headquarters_position

        headquarters_row, headquarters_column = headquarters_position

        defenders = []

        @state["field"].each_with_index do |row, row_index|
          row.each_with_index do |object, column_index|
            next unless object
            next unless object["type"] == "technique"
            next unless object["player_id"].to_s == headquarters["player_id"].to_s
            next unless has_headquarters_defender_ability?(object)

            row_distance = (row_index - headquarters_row).abs
            column_distance = (column_index - headquarters_column).abs

            # Защищают только три соседние клетки штаба.
            next unless row_distance <= 1 && column_distance <= 1
            next if row_distance.zero? && column_distance.zero?

            defenders << {
              technique: object,
              row: row_index,
              column: column_index,
              distance: row_distance + column_distance
            }
          end
        end

        defenders.sort_by do |defender|
          [
            -defender[:technique]["hp"].to_i,
            defender[:distance],
            defender[:row],
            defender[:column]
          ]
        end
      end

      def headquarters_position(headquarters)
        @state["field"].each_with_index do |row, row_index|
          row.each_with_index do |object, column_index|
            next unless object.equal?(headquarters)

            return [row_index, column_index]
          end
        end

        nil
      end

      def has_headquarters_defender_ability?(technique)
        Array(technique["abilities"]).any? do |ability|
          ability["code"] == HEADQUARTERS_DEFENDER_ABILITY
        end
      end

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

      def emit_technique_damage(
        technique,
        row,
        column,
        damage,
        hp_before,
        hp_after,
        source
      )
        return unless @events
        return if damage <= 0

        @events << {
          type: "technique_damaged",
          technique: technique_data(technique, row, column),
          damage: damage,
          hp_before: hp_before,
          hp_after: hp_after,
          source: source
        }
      end

      def emit_technique_destroyed(technique, row, column, source)
        return unless @events

        @events << {
          type: "technique_destroyed",
          technique: technique_data(technique, row, column),
          source: source
        }
      end

      def technique_data(technique, row, column)
        {
          type: technique["type"],
          player_id: technique["player_id"],
          card_id: technique["card_id"],
          name: technique["name"],
          position: [row, column]
        }
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
