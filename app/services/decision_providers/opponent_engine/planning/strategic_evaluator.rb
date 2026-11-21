module DecisionProviders
  module OpponentEngine
    module Planning
      class StrategicEvaluator
        WIN_SCORE = 1_000_000

        # Уничтожение штаба по-прежнему имеет терминальную оценку WIN_SCORE,
        # поэтому обычное повреждение штаба не должно превосходить уничтожение
        # или подавление боеспособной техники в несколько раз.
        HQ_HP_WEIGHT = 5.0
        HQ_FIREPOWER_WEIGHT = 2.0
        HQ_FUEL_WEIGHT = 0.5

        TECHNIQUE_HP_WEIGHT = 2.5
        TECHNIQUE_FIREPOWER_WEIGHT = 3.0
        TECHNIQUE_RANGE_WEIGHT = 1.0
        TECHNIQUE_FUEL_WEIGHT = 1.5

        TECHNIQUE_TANK_DESTROYER_ROLE_WEIGHT = 5.0
        TECHNIQUE_ARTILLERY_ROLE_WEIGHT = 6.0

        PLATOON_HP_WEIGHT = 2.0
        PLATOON_FIREPOWER_WEIGHT = 3.0
        PLATOON_ARMOR_WEIGHT = 1.5
        PLATOON_FUEL_WEIGHT = 0.25

        POSITION_WEIGHT = 1.0

        # Наступательная группа оценивается отдельно от непосредственной
        # совместной атаки. Бонус намеренно невелик относительно ценности
        # техники и результата боя: он помогает подготовить поддержку, но не
        # должен заменять выгодную атаку.
        OFFENSIVE_GROUP_FULL_STRENGTH_HP = 4
        OFFENSIVE_GROUP_MAX_SUPPORT_DISTANCE = 2
        OFFENSIVE_GROUP_FIREPOWER_WEIGHT = 0.35
        OFFENSIVE_GROUP_PROGRESS_WEIGHT = 0.5

        DEPLOYMENT_SLOT_WEIGHT = 5.0

        # Построение ударной линии рядом со штабом.
        OFFENSIVE_LANE_PAIR_WEIGHT = 5.0
        OFFENSIVE_LANE_FIREPOWER_WEIGHT = 0.35
        OFFENSIVE_LANE_MAX_SCORE = 16.0

        COMBINED_ATTACK_MIN_TECHNIQUES = 1
        COMBINED_ATTACK_OPPORTUNITY_WEIGHT = 0.75

        RESOURCE_WEIGHT = 1.5
        HAND_CARD_WEIGHT = 1.0

        ENEMY_THREAT_WEIGHT = 0.5
        HEADQUARTERS_ATTACK_OPPORTUNITY_WEIGHT = 0.5

        # Оценка ожидания следующего хода ради совместной атаки
        WAITING_OPPORTUNITY_WEIGHT = 0.5
        WAITING_OPPORTUNITY_MAX_SCORE = 18.0
        WAITING_RISK_SCALE = 20.0

        # Строй. Техника должна накапливаться на линии построения и выходить
        # вперёд группой. Штраф действует только в конце собственного хода.
        FORMATION_ADVANCE_DISTANCE = 2
        FORMATION_MIN_GROUP = 3
        LONE_ADVANCE_PENALTY = 14.0
        LONE_ADVANCE_FIRED_FACTOR = 0.5
        FORMATION_PATIENCE_DECK_CARDS = 4.0

        # Гонка пустых колод. Взятие карты из пустой колоды наносит штабу
        # урон 1, 2, 3, ... Проигрывает тот, чей штаб погибнет раньше.
        DECK_RACE_WEIGHT = 6.0
        DECK_RACE_HORIZON_DRAWS = 10
        DECK_RACE_MAX_MARGIN = 4

        def self.call(visible_state:, player_id:, profile: nil)
          new(
            visible_state: visible_state,
            player_id: player_id,
            profile: profile,
            profile_scope: :evaluate
          ).call
        end

        def initialize(
          visible_state:,
          player_id:,
          profile: nil,
          profile_scope: :evaluate
        )
          @visible_state = visible_state
          @player_id = player_id.to_s

          @field = @visible_state.fetch("field")
          @players = @visible_state.fetch("players")

          @player = @players.fetch(@player_id)

          @opponent_id = @players.keys.find do |id|
            id.to_s != @player_id
          end

          @opponent = @opponent_id ? @players.fetch(@opponent_id) : {}

          @profile = profile
          @profile_scope = profile_scope

          # Локальные кэши производных расчётов.
          # Живут только в пределах одного StrategicEvaluator.
          @potential_movement_states = {}
          @attack_positions_cache = {}

          # Состояние evaluator не изменяется при расчётах.
          # Поэтому списки объектов поля и техники можно переиспользовать.
          @field_objects_cache = nil
          @own_techniques_cache = nil
          @enemy_techniques_cache = nil
        end

        def call
          terminal = measure_component(:terminal) do
            terminal_score
          end

          return terminal unless terminal.nil?

          measure_component(:headquarters) { headquarters_score } +
            measure_component(:techniques) { techniques_score } +
            measure_component(:platoons) { platoons_score } +
            measure_component(:positioning) { positional_score } +
            measure_component(:offensive_group) { offensive_group_score } +
            measure_component(:offensive_lane) { offensive_lane_score } +
            measure_component(:deployment_capacity) { deployment_capacity_score } +
            measure_component(:headquarters_attack_opportunity) do
              headquarters_attack_opportunity_score
            end +
            measure_component(:combined_attack_opportunity) do
              combined_attack_opportunity_score
            end +
            measure_component(:future_coordination_opportunity) do
              future_coordination_opportunity_score
            end +
            measure_component(:resources) { resources_score } +
            measure_component(:deck_race) { deck_race_score } -
            measure_component(:enemy_threat) { enemy_threat_score } -
            measure_component(:formation_penalty) { formation_penalty }
        end

        # Возвращает составляющие стратегической оценки для диагностики.
        # Не меняет правила оценки и не используется при выборе действий.
        def score_breakdown
          terminal = measure_component(:terminal) do
            terminal_score
          end

          return { terminal: terminal } unless terminal.nil?

          {
            headquarters: measure_component(:headquarters) { headquarters_score },
            techniques: measure_component(:techniques) { techniques_score },
            platoons: measure_component(:platoons) { platoons_score },
            positioning: measure_component(:positioning) { positional_score },
            offensive_group: measure_component(:offensive_group) { offensive_group_score },
            offensive_lane: measure_component(:offensive_lane) { offensive_lane_score },
            deployment_capacity: measure_component(:deployment_capacity) { deployment_capacity_score },
            headquarters_attack_opportunity: measure_component(:headquarters_attack_opportunity) do
              headquarters_attack_opportunity_score
            end,
            combined_attack_opportunity: measure_component(:combined_attack_opportunity) do
              combined_attack_opportunity_score
            end,
            future_coordination_opportunity: measure_component(:future_coordination_opportunity) do
              future_coordination_opportunity_score
            end,
            resources: measure_component(:resources) { resources_score },
            deck_race: measure_component(:deck_race) { deck_race_score },
            enemy_threat: -measure_component(:enemy_threat) { enemy_threat_score },
            formation_penalty: -measure_component(:formation_penalty) { formation_penalty }
          }
        end

        private

        def measure_component(name)
          return yield unless @profile

          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          yield
        ensure
          if @profile && started_at
            elapsed_ms = (
              Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
            ) * 1000

            key = :"#{@profile_scope}.#{name}"

            stats = (@profile[key] ||= {
              calls: 0,
              total_ms: 0.0,
              max_ms: 0.0
            })

            stats[:calls] += 1
            stats[:total_ms] += elapsed_ms
            stats[:max_ms] = [stats[:max_ms], elapsed_ms].max
          end
        end

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
            numeric(technique, "fuel") * TECHNIQUE_FUEL_WEIGHT +
            technique_role_value(technique)
        end

        def technique_role_value(technique)
          case technique["technique_type"]
          when "tank_destroyer"
            TECHNIQUE_TANK_DESTROYER_ROLE_WEIGHT
          when "artillery"
            TECHNIQUE_ARTILLERY_ROLE_WEIGHT
          else
            0
          end
        end

        def own_techniques
          @own_techniques_cache ||= field_objects.select do |object, _position|
            object["type"] == "technique" &&
              owner_sign(object["player_id"]) == 1
          end.freeze
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
        # Наступательная группировка
        # --------------------------------------------------------------

        # Поощряет здоровую технику, которая уже заняла позицию поддержки
        # передовой машины у конкретной видимой цели. Это не оценка урона:
        # непосредственная выгода совместной атаки остаётся ответственностью
        # ForceCoordinationEvaluator.
        #
        # Поэтому в группу не включается техника, которая уже сама может
        # атаковать ту же цель в этом ходу. Такая ситуация будет учтена
        # combined_attack_opportunity_score и не должна считаться
        # дважды.
        def offensive_group_score
          own_headquarters = headquarters_position(@player_id)
          enemy_headquarters = headquarters_position(@opponent_id)

          return 0 unless own_headquarters && enemy_headquarters

          available_techniques = own_techniques.select do |technique, _position|
            numeric(technique, "hp").positive?
          end

          return 0 if available_techniques.length < 2

          offensive_targets.sum do |target, target_position|
            offensive_group_score_for_target(
              target: target,
              target_position: target_position,
              own_headquarters: own_headquarters,
              techniques: available_techniques
            )
          end
        end

        # --------------------------------------------------------------
        # Построение ударной линии
        # --------------------------------------------------------------

        def offensive_lane_score
          own_headquarters = headquarters_position(@player_id)
          return 0 unless own_headquarters

          lane_column =
            case own_headquarters[1]
            when 0 then 1
            when 4 then 3
            else return 0
            end

          lane_techniques = own_techniques.select do |technique, position|
            position[1] == lane_column &&
              numeric(technique, "hp").positive?
          end

          # Одна машина ещё не образует ударную группу.
          return 0 if lane_techniques.length < 2

          group_firepower = lane_techniques.sum do |technique, _position|
            health_factor = [
              numeric(technique, "hp").to_f /
                OFFENSIVE_GROUP_FULL_STRENGTH_HP,
              1.0
            ].min

            numeric(technique, "firepower") * health_factor
          end

          group_size_bonus =
            (lane_techniques.length - 1) * OFFENSIVE_LANE_PAIR_WEIGHT

          (
            group_size_bonus +
            group_firepower * OFFENSIVE_LANE_FIREPOWER_WEIGHT
          ).clamp(0, OFFENSIVE_LANE_MAX_SCORE)
        end

        def offensive_group_score_for_target(
          target:,
          target_position:,
          own_headquarters:,
          techniques:
        )
          leaders = techniques.select do |technique, position|
            attack_positions_for(
              technique,
              position,
              target,
              target_position
            ).any?
          end

          return 0 if leaders.empty?

          # Один танк поддержки получает только один лучший бонус: иначе
          # несколько передовых машин искусственно умножили бы его ценность.
          techniques.sum do |supporter, supporter_position|
            next 0 if leaders.any? { |_leader, position| position == supporter_position }

            best_support_score_for(
              supporter: supporter,
              supporter_position: supporter_position,
              leaders: leaders,
              target: target,
              target_position: target_position,
              own_headquarters: own_headquarters
            )
          end
        end

        def best_support_score_for(
          supporter:,
          supporter_position:,
          leaders:,
          target:,
          target_position:,
          own_headquarters:
        )
          # Если машина уже может участвовать в атаке, её боевой вклад
          # оценивает ForceCoordinationEvaluator.
          return 0 if attack_positions_for(
            supporter,
            supporter_position,
            target,
            target_position
          ).any?

          return 0 unless offensive_group_mobile?(supporter)

          supporter_progress = progress_from_headquarters(
            supporter_position,
            own_headquarters
          )

          return 0 unless supporter_progress.positive?

          leaders.filter_map do |leader, leader_position|
            leader_progress = progress_from_headquarters(
              leader_position,
              own_headquarters
            )

            next unless leader_progress > supporter_progress

            distance = chebyshev_distance(
              supporter_position,
              leader_position
            )

            next if distance > OFFENSIVE_GROUP_MAX_SUPPORT_DISTANCE
            next unless moves_toward?(
              supporter_position,
              target_position,
              own_headquarters
            )

            support_readiness_score(
              leader: leader,
              supporter: supporter,
              distance: distance,
              supporter_progress: supporter_progress
            )
          end.max || 0
        end

        def offensive_targets
          field_objects.select do |object, _position|
            owner_sign(object["player_id"]) == -1 &&
              %w[technique headquarters].include?(object["type"])
          end
        end

        def offensive_group_health_factor(technique)
          [
            numeric(technique, "hp").to_f /
              OFFENSIVE_GROUP_FULL_STRENGTH_HP,
            1.0
          ].min
        end

        def offensive_group_mobile?(technique)
          numeric(technique, "movement_count").positive? ||
            numeric(technique, "movement_limit").positive?
        end

        def progress_from_headquarters(position, own_headquarters)
          manhattan_distance(own_headquarters, position)
        end

        def chebyshev_distance(first, second)
          [
            (first[0] - second[0]).abs,
            (first[1] - second[1]).abs
          ].max
        end

        def moves_toward?(position, target_position, own_headquarters)
          manhattan_distance(position, target_position) <
            manhattan_distance(own_headquarters, target_position)
        end

        def support_readiness_score(
          leader:,
          supporter:,
          distance:,
          supporter_progress:
        )
          shared_firepower = [
            numeric(leader, "firepower"),
            numeric(supporter, "firepower")
          ].min

          proximity = OFFENSIVE_GROUP_MAX_SUPPORT_DISTANCE + 1 - distance

          readiness_score =
            proximity * shared_firepower * OFFENSIVE_GROUP_FIREPOWER_WEIGHT +
            supporter_progress * OFFENSIVE_GROUP_PROGRESS_WEIGHT

          readiness_score * [
            offensive_group_health_factor(leader),
            offensive_group_health_factor(supporter)
          ].min
        end

        # --------------------------------------------------------------
        # Свободные клетки для размещения новой техники
        # --------------------------------------------------------------

        def deployment_positions_for(player_id)
          position = headquarters_position(player_id)
          return [] unless position

          GameEngine::Rules::Position.neighbors(position)
        end

        def deployment_capacity_score
          has_free_position = deployment_positions_for(@player_id).any? do |position|
            object_at(position).nil?
          end

          has_free_position ? DEPLOYMENT_SLOT_WEIGHT : 0
        end

        # --------------------------------------------------------------
        # Состояние без «потраченных» атак
        # --------------------------------------------------------------

        def own_turn?
          @visible_state["current_player_id"].to_s == @player_id
        end

        # После end_turn отметки has_attacked и has_counterattacked нашей
        # техники и штаба остаются в состоянии, но в начале следующего
        # собственного хода они сбрасываются. Поэтому «возможность атаки»
        # в конце хода нужно оценивать так, будто выстрелы ещё не потрачены.
        # Иначе выстрел штаба или танка выглядит потерей возможности, и ИИ
        # предпочитает не стрелять.
        #
        # Перемещение здесь не сбрасывается: его отдельно учитывает
        # future_coordination_opportunity_score.
        def attack_flags_cleared_evaluator
          @attack_flags_cleared_evaluator ||= self.class.new(
            visible_state: state_with_attack_flags_cleared,
            player_id: @player_id
          )
        end

        def state_with_attack_flags_cleared
          state = @visible_state.deep_dup

          state["current_player_id"] = @player_id

          state["available_actions"] = {
            "field" => {},
            "hand" => {}
          }

          state["field"].each do |row|
            row.each do |object|
              next unless object
              next unless object["player_id"].to_s == @player_id
              next unless %w[technique headquarters].include?(object["type"])

              object["has_attacked"] = false
              object["has_counterattacked"] = false
            end
          end

          state
        end

        # --------------------------------------------------------------
        # Строй: выдвижение вперёд только группой
        # --------------------------------------------------------------

        # Выдвинутой считается техника, ушедшая от собственного штаба
        # минимум на FORMATION_ADVANCE_DISTANCE столбца. Если таких машин
        # меньше требуемой группы, каждая получает штраф.
        #
        # Машина, которая в этом ходу уже стреляла, штрафуется слабее:
        # её польза (урон, уничтожение цели) уже учтена в материальной
        # оценке. Выход вперёд без выстрела штрафуется полностью.
        #
        # Внутри хода штраф не применяется, чтобы поиск мог построить
        # групповое выдвижение из нескольких перемещений подряд.
        def formation_penalty
          return 0 if own_turn?

          own_headquarters = headquarters_position(@player_id)
          return 0 unless own_headquarters

          healthy = own_techniques.select do |technique, _position|
            numeric(technique, "hp").positive?
          end

          forward = healthy.select do |_technique, position|
            (position[1] - own_headquarters[1]).abs >=
              FORMATION_ADVANCE_DISTANCE
          end

          return 0 if forward.empty?

          required_group = [
            FORMATION_MIN_GROUP,
            [healthy.length, 2].max
          ].min

          return 0 if forward.length >= required_group

          forward.sum do |technique, _position|
            factor =
              technique["has_attacked"] ? LONE_ADVANCE_FIRED_FACTOR : 1.0

            LONE_ADVANCE_PENALTY * factor
          end * formation_patience
        end

        # Когда собственная колода почти пуста, ожидание становится
        # дорогим: каждый ход приносит урон штабу. Штраф за одиночный
        # выход плавно ослабевает до нуля.
        def formation_patience
          deck_count = numeric(@player, "deck_count")

          [deck_count / FORMATION_PATIENCE_DECK_CARDS, 1.0].min
        end

        # --------------------------------------------------------------
        # Совместная атака нескольких танков
        # --------------------------------------------------------------

        def combined_attack_opportunity_score
          return attack_flags_cleared_evaluator.send(
            :combined_attack_opportunity_score
          ) unless own_turn?

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
        # Выгода ожидания следующего хода для совместной атаки
        # --------------------------------------------------------------

        def future_coordination_opportunity_score
          # Оценка применяется только после завершения нашего хода.
          return 0 if @visible_state["current_player_id"].to_s == @player_id

          current_gain =
            attack_flags_cleared_evaluator.send(:best_combined_attack_gain)

          projected_state = project_next_own_turn

          projected_evaluator = self.class.new(
            visible_state: projected_state,
            player_id: @player_id
          )

          future_gain =
            projected_evaluator.send(:best_combined_attack_gain)

          additional_gain = [
            future_gain - current_gain,
            0
          ].max

          return 0 unless additional_gain.positive?

          # Чем выше угроза противника, тем меньше ценность ожидания.
          risk = enemy_threat_score

          risk_multiplier =
            1.0 / (1.0 + risk / WAITING_RISK_SCALE)

          [
            additional_gain *
              WAITING_OPPORTUNITY_WEIGHT *
              risk_multiplier,
            WAITING_OPPORTUNITY_MAX_SCORE
          ].min
        end

        # --------------------------------------------------------------
        # Лучшая абсолютная выгода совместной атаки
        # --------------------------------------------------------------

        def best_combined_attack_gain
          enemy_techniques.map do |target, target_position|
            attackers = potential_attackers(
              target,
              target_position
            )

            next 0 if attackers.length < COMBINED_ATTACK_MIN_TECHNIQUES

            analysis =
              ForceCoordinationEvaluator.analyze(
                visible_state: @visible_state,
                player_id: @player_id,
                target_position: target_position,
                attackers: attackers,
                material_scorer: method(:combat_material_score)
              )

            analysis.best_combined_gain
          end.max || 0
        end

        # --------------------------------------------------------------
        # Гипотетическое начало следующего собственного хода
        # --------------------------------------------------------------

        def project_next_own_turn
          state = @visible_state.deep_dup

          state["current_player_id"] = @player_id

          # Доступные действия будут вычисляться по правилам движения,
          # а не использовать устаревшие действия предыдущего хода.
          state["available_actions"] = {
            "field" => {},
            "hand" => {}
          }

          state["field"].each do |row|
            row.each do |object|
              next unless object
              next unless object["player_id"].to_s == @player_id

              case object["type"]
              when "technique"
                object["movement_count"] =
                  numeric(object, "movement_limit").to_i

                object["has_attacked"] = false
                object["has_counterattacked"] = false
              when "headquarters"
                object["has_attacked"] = false
                object["has_counterattacked"] = false
              end
            end
          end

          state
        end

        # --------------------------------------------------------------
        # Возможность штабной атаки после перемещения разведчика
        # --------------------------------------------------------------

        def headquarters_attack_opportunity_score
          return attack_flags_cleared_evaluator.send(
            :headquarters_attack_opportunity_score
          ) unless own_turn?

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

          return 0 unless
            simulated_state["field"][target_position[0]][target_position[1]].nil?

          score_after = combat_material_score(simulated_state)

          [score_after - score_before, 0].max
        end

        def potential_attackers(target, target_position)
          own_techniques.filter_map do |technique, position|
            next if technique["has_attacked"]

            attack_positions = attack_positions_for(
              technique,
              position,
              target,
              target_position
            )

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

        def attack_positions_for(
          technique,
          position,
          target,
          target_position
        )
          return [] if technique["has_attacked"]

          cache_key = [position, target_position]

          cached_positions = @attack_positions_cache[cache_key]

          return cached_positions.dup if cached_positions

          possible_positions = [
            position,
            *available_move_positions(
              position,
              technique: technique
            )
          ].uniq

          attack_positions = possible_positions.filter_map do |attack_position|
            state, attacker = potential_movement_state(
              position,
              attack_position
            )

            simulated_target =
              state["field"][target_position[0]][target_position[1]]

            next unless simulated_target
            next unless simulated_target["player_id"].to_s == target["player_id"].to_s

            next unless GameEngine::Rules::AttackTarget.valid?(
              state: state,
              attacker: attacker,
              target: simulated_target,
              attacker_position: attack_position,
              target_position: target_position
            )

            attack_position
          end

          @attack_positions_cache[cache_key] = attack_positions

          attack_positions.dup
        end

        def available_move_positions(position, technique:)
          field_actions =
            @visible_state.dig("available_actions", "field") || {}

          actions = field_actions[position.join(",")]

          # Если для техники есть рассчитанные сервером действия,
          # используем именно их.
          return Array(actions["moves"]) if actions

          # После end_turn серверные available_actions пусты.
          # Для гипотетического следующего хода рассчитываем
          # доступные перемещения по существующим игровым правилам.
          return [] unless numeric(technique, "movement_count").positive?

          GameEngine::Rules::Position.neighbors(position).select do |next_position|
            object_at(next_position).nil? &&
              GameEngine::Rules::TechniqueMovement.valid?(
                technique,
                position,
                next_position
              )
          end
        end

        def potential_movement_state(from, to)
          return [
            @visible_state,
            @visible_state["field"][from[0]][from[1]]
          ] if from == to

          cache_key = [from, to]

          @potential_movement_states[cache_key] ||= begin
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
        end

        # --------------------------------------------------------------
        # Угроза от вражеской техники
        # --------------------------------------------------------------

        def enemy_threat_score
          return @enemy_threat_score if defined?(@enemy_threat_score)

          total_threat = enemy_techniques.sum do |technique, position|
            potential_enemy_positions(technique, position).map do |state, attacker, attacker_position|
              target_positions = state_field_objects(state).filter_map do |target, target_position|
                next unless owner_sign(target["player_id"]) == 1
                next unless %w[technique headquarters].include?(target["type"])

                next unless GameEngine::Rules::AttackTarget.valid?(
                  state: state,
                  attacker: attacker,
                  target: target,
                  attacker_position: attacker_position,
                  target_position: target_position
                )

                target_position
              end

              next 0 if target_positions.empty?

              # Исходная материальная оценка одинакова для всех
              # потенциальных атак из одной позиции.
              score_before = combat_material_score(state)

              target_positions.map do |target_position|
                potential_attack_threat(
                  state: state,
                  attacker_position: attacker_position,
                  target_position: target_position,
                  score_before: score_before
                )
              end.max || 0
            end.max || 0
          end

          @enemy_threat_score = total_threat * ENEMY_THREAT_WEIGHT
        end

        def enemy_techniques
          @enemy_techniques_cache ||= field_objects.select do |object, _position|
            object["type"] == "technique" &&
              owner_sign(object["player_id"]) == -1
          end.freeze
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

        def potential_attack_threat(
          state:,
          attacker_position:,
          target_position:,
          score_before:
        )
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
        # Гонка пустых колод
        # --------------------------------------------------------------

        # Сравнивает, чей штаб раньше погибнет только от урона пустой
        # колоды, если ни один игрок больше не будет атаковать. Пока обе
        # колоды далеко от конца, оценка равна нулю.
        def deck_race_score
          own_step = deck_death_step(@player_id, own_draws: true)
          enemy_step = deck_death_step(@opponent_id, own_draws: false)

          return 0 if own_step.nil? && enemy_step.nil?

          margin =
            if own_step.nil?
              DECK_RACE_MAX_MARGIN
            elsif enemy_step.nil?
              -DECK_RACE_MAX_MARGIN
            else
              (own_step - enemy_step).clamp(
                -DECK_RACE_MAX_MARGIN,
                DECK_RACE_MAX_MARGIN
              )
            end

          margin * DECK_RACE_WEIGHT
        end

        # Номер шага (1, 2, 3...) глобальной очереди взятий карт, на
        # котором штаб игрока погибнет. Взятия чередуются; первым берёт
        # карту тот, чей ход начнётся следующим. Если игрок переживёт
        # горизонт расчёта, возвращает nil.
        def deck_death_step(player_id, own_draws:)
          return nil unless player_id

          player = @players[player_id.to_s]
          headquarters = headquarters_for(player_id)

          return nil unless player && headquarters

          hp = numeric(headquarters, "hp")
          deck = numeric(player, "deck_count").to_i
          attempts = numeric(player, "empty_deck_draw_attempts").to_i

          platoons = Array(player["platoons"]).compact.map do |platoon|
            { armor: numeric(platoon, "armor"), hp: numeric(platoon, "hp") }
          end

          # В конце нашего хода противник уже взял карту, следующим берёт
          # карту наш ИИ. Внутри нашего хода следующим берёт противник.
          ai_draws_next = !own_turn?

          DECK_RACE_HORIZON_DRAWS.times do |index|
            if deck.positive?
              deck -= 1
              next
            end

            attempts += 1
            damage = attempts.to_f

            platoons.each do |platoon|
              break if damage <= 0
              next if platoon[:hp] <= 0

              absorbed = [damage, platoon[:armor]].min
              platoon[:hp] -= absorbed
              damage -= absorbed
            end

            hp -= damage

            next unless hp <= 0

            draw_number = index + 1

            drawer_is_ai = own_draws
            first_is_ai = ai_draws_next

            return(
              if drawer_is_ai == first_is_ai
                2 * draw_number - 1
              else
                2 * draw_number
              end
            )
          end

          nil
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
          @field_objects_cache ||= @field.each_with_index.flat_map do |row, row_index|
            row.each_with_index.filter_map do |object, column_index|
              next unless object

              [
                object,
                [row_index, column_index]
              ]
            end
          end.freeze
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
