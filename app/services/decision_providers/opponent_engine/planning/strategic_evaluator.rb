
module DecisionProviders
  module OpponentEngine
    module Planning
      class StrategicEvaluator
        WIN_SCORE = 1_000_000

        HQ_HP_WEIGHT = 12.0
        HQ_FIREPOWER_WEIGHT = 2.0
        HQ_FUEL_WEIGHT = 0.5

        TECHNIQUE_HP_WEIGHT = 2.5
        TECHNIQUE_FIREPOWER_WEIGHT = 3.0
        TECHNIQUE_RANGE_WEIGHT = 1.0
        TECHNIQUE_FUEL_WEIGHT = 0.25

        PLATOON_HP_WEIGHT = 2.0
        PLATOON_FIREPOWER_WEIGHT = 3.0
        PLATOON_ARMOR_WEIGHT = 1.5
        PLATOON_FUEL_WEIGHT = 0.25

        POSITION_WEIGHT = 1.5

        DEPLOYMENT_SLOT_WEIGHT = 5.0

        ATTACK_FORCE_MIN_TECHNIQUES = 2
        ATTACK_FORCE_MIN_FIREPOWER = 6.0
        ATTACK_FORCE_BASE_BONUS = 6.0
        ATTACK_FORCE_TECHNIQUE_WEIGHT = 2.0
        ATTACK_FORCE_FIREPOWER_WEIGHT = 0.5

        RESOURCE_WEIGHT = 1.5
        HAND_CARD_WEIGHT = 1.0

        def self.call(visible_state:, player_id:)
          new(
            visible_state: visible_state,
            player_id: player_id
          ).call
        end

        def initialize(visible_state:, player_id:)
          @visible_state = visible_state
          @player_id = player_id.to_s

          @field = @visible_state.fetch("field")
          @players = @visible_state.fetch("players")

          @player = @players.fetch(@player_id)

          @opponent_id = @players.keys.find do |id|
            id.to_s != @player_id
          end

          @opponent = @opponent_id ? @players.fetch(@opponent_id) : {}
        end

        def call
          terminal_score || (
            headquarters_score +
            techniques_score +
            platoons_score +
            positional_score +
            deployment_capacity_score +
            attack_force_score +
            resources_score
          )
        end

        private

        # --------------------------------------------------------------
        # Завершение партии
        # --------------------------------------------------------------

        def terminal_score
          return nil unless @visible_state["status"] == "finished"

          result = @visible_state["result"] || {}

          winner_id = result["winner_id"] || result[:winner_id]
          loser_id = result["loser_id"] || result[:loser_id]

          return WIN_SCORE if winner_id.to_s == @player_id
          return -WIN_SCORE if loser_id.to_s == @player_id

          0
        end

        # --------------------------------------------------------------
        # Штабы
        # --------------------------------------------------------------

        def headquarters_score
          own_headquarters = headquarters_for(@player_id)
          enemy_headquarters = headquarters_for(@opponent_id)

          headquarters_value(own_headquarters) -
            headquarters_value(enemy_headquarters)
        end

        def headquarters_value(headquarters)
          return 0 unless headquarters

          numeric(headquarters, "hp") * HQ_HP_WEIGHT +
            numeric(headquarters, "firepower") * HQ_FIREPOWER_WEIGHT +
            numeric(headquarters, "fuel") * HQ_FUEL_WEIGHT
        end

        def headquarters_for(player_id)
          return nil unless player_id

          field_objects.find do |object, _position|
            object["type"] == "headquarters" &&
              object["player_id"].to_s == player_id.to_s
          end&.first
        end

        # --------------------------------------------------------------
        # Техника
        # --------------------------------------------------------------

        def techniques_score
          field_objects.sum do |object, _position|
            next 0 unless object["type"] == "technique"

            sign = owner_sign(object["player_id"])
            next 0 if sign.zero?

            sign * technique_value(object)
          end
        end

        def technique_value(technique)
          numeric(technique, "hp") * TECHNIQUE_HP_WEIGHT +
            numeric(technique, "firepower") * TECHNIQUE_FIREPOWER_WEIGHT +
            numeric(technique, "attack_range") * TECHNIQUE_RANGE_WEIGHT +
            numeric(technique, "fuel") * TECHNIQUE_FUEL_WEIGHT
        end

        def own_techniques
          field_objects.select do |object, _position|
            object["type"] == "technique" &&
              owner_sign(object["player_id"]) == 1
          end
        end

        # --------------------------------------------------------------
        # Взводы
        # --------------------------------------------------------------

        def platoons_score
          @players.sum do |player_id, player|
            sign = owner_sign(player_id)
            next 0 if sign.zero?

            Array(player["platoons"]).compact.sum do |platoon|
              sign * platoon_value(platoon)
            end
          end
        end

        def platoon_value(platoon)
          numeric(platoon, "hp") * PLATOON_HP_WEIGHT +
            numeric(platoon, "firepower") * PLATOON_FIREPOWER_WEIGHT +
            numeric(platoon, "armor") * PLATOON_ARMOR_WEIGHT +
            numeric(platoon, "fuel") * PLATOON_FUEL_WEIGHT
        end

        # --------------------------------------------------------------
        # Позиции на поле
        # --------------------------------------------------------------

        def positional_score
          own_headquarters = headquarters_position(@player_id)
          enemy_headquarters = headquarters_position(@opponent_id)

          return 0 unless own_headquarters && enemy_headquarters

          own_score = own_techniques.sum do |_technique, position|
            progress_toward(
              position,
              enemy_headquarters,
              POSITION_WEIGHT
            )
          end

          enemy_score = field_objects.sum do |object, position|
            next 0 unless object["type"] == "technique"
            next 0 unless owner_sign(object["player_id"]) == -1

            progress_toward(
              position,
              own_headquarters,
              POSITION_WEIGHT
            )
          end

          own_score - enemy_score
        end

        def progress_toward(position, target, weight)
          max_distance =
            (@field.length - 1) +
            (@field.first.length - 1)

          distance = manhattan_distance(position, target)

          (max_distance - distance) * weight
        end

        def manhattan_distance(first, second)
          (first[0] - second[0]).abs +
            (first[1] - second[1]).abs
        end

        def headquarters_position(player_id)
          return nil unless player_id

          field_objects.find do |object, _position|
            object["type"] == "headquarters" &&
              object["player_id"].to_s == player_id.to_s
          end&.last
        end

        # --------------------------------------------------------------
        # Тыловое накопление техники
        # --------------------------------------------------------------

        def deployment_positions_for(player_id)
          position = headquarters_position(player_id)
          return [] unless position

          GameEngine::Rules::Position.neighbors(position)
        end

        # --------------------------------------------------------------
        # Свободные клетки для размещения новой техники
        # --------------------------------------------------------------

        def deployment_capacity_score
          deployment_positions_for(@player_id).count do |position|
            object_at(position).nil?
          end * DEPLOYMENT_SLOT_WEIGHT
        end

        # --------------------------------------------------------------
        # Накопленная сила для наступления
        # --------------------------------------------------------------

        def attack_force_score
          own_headquarters = headquarters_position(@player_id)
          enemy_headquarters = headquarters_position(@opponent_id)

          return 0 unless own_headquarters && enemy_headquarters

          field_objects.sum do |target, target_position|
            next 0 unless target["type"] == "technique"
            next 0 unless owner_sign(target["player_id"]) == -1

            available_attackers = own_techniques.select do |technique, attacker_position|
              next false if technique["has_attacked"]

              GameEngine::Rules::AttackTarget.valid?(
                state: @visible_state,
                attacker: technique,
                target: target,
                attacker_position: attacker_position,
                target_position: target_position
              )
            end

            technique_count = available_attackers.length

            next 0 if technique_count < ATTACK_FORCE_MIN_TECHNIQUES

            total_firepower = available_attackers.sum do |technique, _position|
              numeric(technique, "firepower")
            end

            next 0 if total_firepower < ATTACK_FORCE_MIN_FIREPOWER

            target_hp = numeric(target, "hp")

            next 0 unless target_hp.positive?

            attack_readiness = [
              total_firepower / target_hp,
              1.0
            ].min

            base_bonus =
              ATTACK_FORCE_BASE_BONUS +
              (technique_count - ATTACK_FORCE_MIN_TECHNIQUES) *
                ATTACK_FORCE_TECHNIQUE_WEIGHT +
              (total_firepower - ATTACK_FORCE_MIN_FIREPOWER) *
                ATTACK_FORCE_FIREPOWER_WEIGHT

            base_bonus * attack_readiness
          end
        end

        # --------------------------------------------------------------
        # Ресурсы и карты
        # --------------------------------------------------------------

        def resources_score
          own_resources = numeric(@player, "resources")
          enemy_resources = numeric(@opponent, "resources")

          own_hand_count = Array(@player["hand"]).length
          enemy_hand_count = numeric(@opponent, "hand_count")

          (own_resources - enemy_resources) * RESOURCE_WEIGHT +
            (own_hand_count - enemy_hand_count) * HAND_CARD_WEIGHT
        end

        # --------------------------------------------------------------
        # Общие вспомогательные методы
        # --------------------------------------------------------------

        def field_objects
          @field.each_with_index.flat_map do |row, row_index|
            row.each_with_index.filter_map do |object, column_index|
              next unless object

              [
                object,
                [row_index, column_index]
              ]
            end
          end
        end

        def object_at(position)
          @field.dig(position[0], position[1])
        end

        def own_object?(object)
          object["player_id"].to_s == @player_id
        end

        def owner_sign(player_id)
          return 1 if player_id.to_s == @player_id
          return -1 if @opponent_id && player_id.to_s == @opponent_id.to_s

          0
        end

        def numeric(object, key)
          (object[key] || 0).to_f
        end
      end
    end
  end
end
