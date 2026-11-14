
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
        COMBINED_ATTACK_MIN_TECHNIQUES = 2
        COMBINED_ATTACK_OPPORTUNITY_WEIGHT = 0.75

        RESOURCE_WEIGHT = 1.5
        HAND_CARD_WEIGHT = 1.0

        ENEMY_THREAT_WEIGHT = 0.5
        HEADQUARTERS_ATTACK_OPPORTUNITY_WEIGHT = 0.5

        # Накопление техники около собственного штаба
        STAGING_COLUMNS = 2
        STAGING_MIN_TECHNIQUES = 2
        STAGING_BASE_BONUS = 8.0
        STAGING_TECHNIQUE_WEIGHT = 3.0
        STAGING_FIREPOWER_WEIGHT = 1.0

        # Ограничение бонуса за чрезмерное накопление
        STAGING_MAX_TECHNIQUES = 4
        STAGING_MAX_FIREPOWER = 12.0

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
            staging_force_score +
            headquarters_attack_opportunity_score +
            combined_attack_opportunity_score +
            resources_score -
            enemy_threat_score
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
          return 0 unless headquarters_for(@player_id)
          return 0 unless headquarters_for(@opponent_id)

          field_objects.sum do |target, target_position|
            next 0 unless target["type"] == "technique"
            next 0 unless owner_sign(target["player_id"]) == -1

            attackers = potential_attackers(
              target,
              target_position
            )

            attacker_count = attackers.length

            next 0 if attacker_count < ATTACK_FORCE_MIN_TECHNIQUES

            total_firepower = attackers.sum do |attacker|
              attacker[:firepower]
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
              (attacker_count - ATTACK_FORCE_MIN_TECHNIQUES) *
                ATTACK_FORCE_TECHNIQUE_WEIGHT +
              (total_firepower - ATTACK_FORCE_MIN_FIREPOWER) *
                ATTACK_FORCE_FIREPOWER_WEIGHT

            base_bonus * attack_readiness
          end
        end

        # --------------------------------------------------------------
        # Накопление техники около собственного штаба
        # --------------------------------------------------------------

        def staging_force_score
          own_staging_force = staging_force_for(@player_id)
          enemy_staging_force = staging_force_for(@opponent_id)

          own_staging_force - enemy_staging_force
        end

        def staging_force_for(player_id)
          return 0 unless player_id

          own_headquarters_position = headquarters_position(player_id)
          return 0 unless own_headquarters_position

          field_width = @field.first.length
          headquarters_column = own_headquarters_position[1]

          staging_columns =
            if headquarters_column < field_width / 2
              0...STAGING_COLUMNS
            else
              (field_width - STAGING_COLUMNS)...field_width
            end

          staging_techniques = field_objects.filter_map do |object, position|
            next unless object["type"] == "technique"
            next unless object["player_id"].to_s == player_id.to_s
            next unless staging_columns.cover?(position[1])

            object
          end

          technique_count = staging_techniques.length

          return 0 if technique_count < STAGING_MIN_TECHNIQUES

          total_firepower = staging_techniques.sum do |technique|
            numeric(technique, "firepower")
          end

          evaluated_technique_count = [
            technique_count,
            STAGING_MAX_TECHNIQUES
          ].min

          evaluated_firepower = [
            total_firepower,
            STAGING_MAX_FIREPOWER
          ].min

          STAGING_BASE_BONUS +
            (evaluated_technique_count - STAGING_MIN_TECHNIQUES) *
              STAGING_TECHNIQUE_WEIGHT +
            evaluated_firepower * STAGING_FIREPOWER_WEIGHT
        end

        # --------------------------------------------------------------
        # Совместная атака нескольких танков
        # --------------------------------------------------------------

        def combined_attack_opportunity_score
          enemy_techniques.sum do |target, target_position|
            attackers = potential_attackers(
              target,
              target_position
            )

            next 0 if attackers.length < COMBINED_ATTACK_MIN_TECHNIQUES

            coordination_bonus =
              ForceCoordinationEvaluator.call(
                visible_state: @visible_state,
                player_id: @player_id,
                target_position: target_position,
                attackers: attackers,
                material_scorer: method(:combat_material_score)
              )

            coordination_bonus * COMBINED_ATTACK_OPPORTUNITY_WEIGHT
          end
        end

        # --------------------------------------------------------------
        # Возможность штабной атаки после перемещения разведчика
        # --------------------------------------------------------------

        def headquarters_attack_opportunity_score
          headquarters = headquarters_for(@player_id)

          return 0 unless headquarters
          return 0 if headquarters["has_attacked"]

          headquarters_position = headquarters_position(@player_id)
          return 0 unless headquarters_position

          best_attack_gain = enemy_techniques.flat_map do |target, target_position|
            own_techniques.flat_map do |technique, technique_position|
              potential_spotting_states(
                technique,
                technique_position
              ).filter_map do |state, _spotter_position|
                simulated_headquarters =
                  state["field"][headquarters_position[0]][headquarters_position[1]]

                simulated_target =
                  state["field"][target_position[0]][target_position[1]]

                next unless simulated_headquarters && simulated_target

                next unless GameEngine::Rules::AttackTarget.valid?(
                  state: state,
                  attacker: simulated_headquarters,
                  target: simulated_target,
                  attacker_position: headquarters_position,
                  target_position: target_position
                )

                headquarters_attack_material_gain(
                  state: state,
                  attacker_position: headquarters_position,
                  target_position: target_position
                )
              end
            end
          end.max || 0

          best_attack_gain * HEADQUARTERS_ATTACK_OPPORTUNITY_WEIGHT
        end

        def potential_spotting_states(technique, position)
          candidates = [
            [@visible_state, position]
          ]

          movement_count = numeric(technique, "movement_count").to_i
          return candidates unless movement_count.positive?

          reachable_positions = {
            position => 0
          }

          queue = [position]

          until queue.empty?
            current_position = queue.shift
            moves_used = reachable_positions.fetch(current_position)

            next if moves_used >= movement_count

            GameEngine::Rules::Position.neighbors(current_position).each do |next_position|
              next if reachable_positions.key?(next_position)
              next unless object_at(next_position).nil?

              next unless GameEngine::Rules::TechniqueMovement.valid?(
                technique,
                current_position,
                next_position
              )

              reachable_positions[next_position] = moves_used + 1
              queue << next_position
            end
          end

          reachable_positions.each do |destination, moves_used|
            next if destination == position

            state = @visible_state.deep_dup

            moved_technique =
              state["field"][position[0]][position[1]]

            moved_technique["movement_count"] -= moves_used

            state["field"][position[0]][position[1]] = nil
            state["field"][destination[0]][destination[1]] = moved_technique

            candidates << [
              state,
              destination
            ]
          end

          candidates
        end

        def headquarters_attack_material_gain(
          state:,
          attacker_position:,
          target_position:
        )
          simulated_state = state.deep_dup

          simulated_state["players"].each_value do |player|
            player["graveyard"] ||= []
          end

          attacker =
            simulated_state["field"][attacker_position[0]][attacker_position[1]]

          target =
            simulated_state["field"][target_position[0]][target_position[1]]

          return 0 unless attacker && target

          scenario = GameEngine::Rules::CombatType.call(
            attacker: attacker,
            target: target,
            attacker_position: attacker_position,
            target_position: target_position
          )

          score_before = combat_material_score(simulated_state)

          attacker["has_attacked"] = true

          GameEngine::Attacks::CombatExecutor.call(
            state: simulated_state,
            attacker_position: attacker_position,
            target_position: target_position,
            scenario: scenario
          )

          score_after = combat_material_score(simulated_state)

          [score_after - score_before, 0].max
        end

        def potential_attackers(target, target_position)
          own_techniques.filter_map do |technique, position|
            next if technique["has_attacked"]

            possible_positions = [
              position,
              *available_move_positions(position)
            ].uniq

            attack_positions = possible_positions.filter_map do |attack_position|
              state, attacker = potential_movement_state(
                position,
                attack_position
              )

              simulated_target =
                state["field"][target_position[0]][target_position[1]]

              next unless simulated_target

              next unless GameEngine::Rules::AttackTarget.valid?(
                state: state,
                attacker: attacker,
                target: simulated_target,
                attacker_position: attack_position,
                target_position: target_position
              )

              attack_position
            end

            attack_positions.sort_by! do |attack_position|
              state, attacker = potential_movement_state(
                position,
                attack_position
              )

              simulated_target =
                state["field"][target_position[0]][target_position[1]]

              scenario = GameEngine::Rules::CombatType.call(
                attacker: attacker,
                target: simulated_target,
                attacker_position: attack_position,
                target_position: target_position
              )

              scenario_priority = {
                ranged: 0,
                normal: 1,
                ptsau_first: 2
              }.fetch(scenario, 3)

              [
                scenario_priority,
                attack_position == position ? 0 : 1
              ]
            end

            next if attack_positions.empty?

            {
              position: position,
              firepower: numeric(technique, "firepower"),
              attack_positions: attack_positions
            }
          end
        end

        def available_move_positions(position)
          field_actions =
            @visible_state.dig("available_actions", "field") || {}

          actions = field_actions[position.join(",")] || {}

          Array(actions["moves"])
        end

        def potential_movement_state(from, to)
          return [
            @visible_state,
            @visible_state["field"][from[0]][from[1]]
          ] if from == to

          state = @visible_state.deep_dup

          technique = state["field"][from[0]][from[1]]

          technique["movement_count"] = [
            numeric(technique, "movement_count").to_i - 1,
            0
          ].max

          state["field"][from[0]][from[1]] = nil
          state["field"][to[0]][to[1]] = technique

          [
            state,
            technique
          ]
        end

        # --------------------------------------------------------------
        # Угроза от вражеской техники
        # --------------------------------------------------------------

        def enemy_threat_score
          total_threat = enemy_techniques.sum do |technique, position|
            potential_enemy_positions(technique, position).map do |state, attacker, attacker_position|
              state_field_objects(state).filter_map do |target, target_position|
                next unless owner_sign(target["player_id"]) == 1
                next unless %w[technique headquarters].include?(target["type"])

                next unless GameEngine::Rules::AttackTarget.valid?(
                  state: state,
                  attacker: attacker,
                  target: target,
                  attacker_position: attacker_position,
                  target_position: target_position
                )

                potential_attack_threat(
                  state: state,
                  attacker_position: attacker_position,
                  target_position: target_position
                )
              end.max || 0
            end.max || 0
          end

          total_threat * ENEMY_THREAT_WEIGHT
        end

        def enemy_techniques
          field_objects.select do |object, _position|
            object["type"] == "technique" &&
              owner_sign(object["player_id"]) == -1
          end
        end

        def potential_enemy_positions(technique, position)
          movement_limit = numeric(technique, "movement_limit").to_i

          initial_state = @visible_state.deep_dup
          initial_technique = initial_state["field"][position[0]][position[1]]

          initial_technique["movement_count"] = movement_limit
          initial_technique["has_attacked"] = false
          initial_technique["has_counterattacked"] = false

          candidates = [
            [initial_state, initial_technique, position]
          ]

          return candidates if movement_limit <= 0

          reachable_positions = { position => 0 }
          queue = [position]

          until queue.empty?
            current_position = queue.shift
            moves_used = reachable_positions.fetch(current_position)

            next if moves_used >= movement_limit

            GameEngine::Rules::Position.neighbors(current_position).each do |next_position|
              next if reachable_positions.key?(next_position)
              next unless object_at(next_position).nil?

              next unless GameEngine::Rules::TechniqueMovement.valid?(
                technique,
                current_position,
                next_position
              )

              reachable_positions[next_position] = moves_used + 1
              queue << next_position
            end
          end

          reachable_positions.each do |destination, moves_used|
            next if destination == position

            state = @visible_state.deep_dup

            moved_technique = state["field"][position[0]][position[1]]

            moved_technique["movement_count"] =
              movement_limit - moves_used

            moved_technique["has_attacked"] = false
            moved_technique["has_counterattacked"] = false

            state["field"][position[0]][position[1]] = nil
            state["field"][destination[0]][destination[1]] = moved_technique

            candidates << [
              state,
              moved_technique,
              destination
            ]
          end

          candidates
        end

        def potential_attack_threat(state:, attacker_position:, target_position:)
          simulated_state = state.deep_dup

          # VisibleState не содержит настоящие кладбища игроков.
          # CombatExecutor использует их при уничтожении объектов.
          simulated_state["players"].each_value do |player|
            player["graveyard"] ||= []
          end

          attacker = simulated_state["field"][attacker_position[0]][attacker_position[1]]
          target = simulated_state["field"][target_position[0]][target_position[1]]

          return 0 unless attacker && target

          attacker["has_attacked"] = true

          scenario = GameEngine::Rules::CombatType.call(
            attacker: attacker,
            target: target,
            attacker_position: attacker_position,
            target_position: target_position
          )

          score_before = combat_material_score(simulated_state)

          GameEngine::Attacks::CombatExecutor.call(
            state: simulated_state,
            attacker_position: attacker_position,
            target_position: target_position,
            scenario: scenario
          )

          score_after = combat_material_score(simulated_state)

          [score_before - score_after, 0].max
        end

        def combat_material_score(state)
          field_score = state_field_objects(state).sum do |object, _position|
            sign = owner_sign(object["player_id"])
            next 0 if sign.zero?

            value =
              case object["type"]
              when "technique"
                technique_value(object)
              when "headquarters"
                headquarters_value(object)
              else
                0
              end

            sign * value
          end

          platoons_score = state["players"].sum do |player_id, player|
            sign = owner_sign(player_id)
            next 0 if sign.zero?

            Array(player["platoons"]).compact.sum do |platoon|
              sign * platoon_value(platoon)
            end
          end

          field_score + platoons_score
        end

        def state_field_objects(state)
          state.fetch("field").each_with_index.flat_map do |row, row_index|
            row.each_with_index.filter_map do |object, column_index|
              next unless object

              [
                object,
                [row_index, column_index]
              ]
            end
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
