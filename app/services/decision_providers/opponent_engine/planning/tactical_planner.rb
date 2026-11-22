
module DecisionProviders
  module OpponentEngine
    module Planning
      class TacticalPlanner
        DEFAULT_DEPTH = 7
        DEFAULT_WIDTH = 20

        # Дополнительная ценность урона по технике,
        # которая уже использовала ответную атаку.
        COUNTERATTACK_SPENT_DAMAGE_BONUS = 1.5

        # Бонус за безопасное уничтожение техники
        # после предварительной дальней атаки штаба.
        SAFE_HEADQUARTERS_FOLLOW_UP_BONUS = 10.0

        # Бонус за перемещение техники с последующей атакой вражеского штаба.
        # Начисляется только после успешной симуляции атаки.
        SAFE_HEADQUARTERS_RAID_BONUS = 8.0

        # Дополнительный множитель для атаки по ослабленному штабу.
        CRITICAL_HEADQUARTERS_HP_RATIO = 0.3
        CRITICAL_HEADQUARTERS_RAID_MULTIPLIER = 1.5

        # Штраф за продвижение с клетки плацдарма без последующей атаки.
        IDLE_ADVANCE_PENALTY = 30.0
        IDLE_MIN_PATIENCE = 0.5

        Node = Data.define(
          :visible_state,
          :actions,
          :steps,
          :score,
          :terminal
        )

        Step = Data.define(
          :action,
          :expected_visible_state
        )

        Result = Data.define(
          :actions,
          :steps,
          :score,
          :expanded_nodes
        )

        def self.call(
          visible_state:,
          player_id:,
          current_time:,
          depth: DEFAULT_DEPTH,
          width: DEFAULT_WIDTH
        )
          new(
            visible_state:,
            player_id:,
            current_time:,
            depth:,
            width:
          ).call
        end

        def initialize(
          visible_state:,
          player_id:,
          current_time:,
          depth:,
          width:
        )
          @visible_state = visible_state
          @player_id = player_id.to_s
          @current_time = current_time

          @depth = Integer(depth)
          @width = Integer(width)

          @root_card_types = Array(
            @visible_state.dig("players", @player_id, "hand")
          ).each_with_object({}) do |card, result|
            result[card["card_id"].to_s] = card["card_type"]
          end

          @root_deployment_positions = root_deployment_positions

          raise ArgumentError, "Depth must be positive" unless @depth.positive?
          raise ArgumentError, "Width must be positive" unless @width.positive?
        end

        def call
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          @phase_timings = Hash.new do |hash, key|
            hash[key] = {
              calls: 0,
              total_ms: 0.0,
              max_ms: 0.0
            }
          end

          @strategic_component_timings = {}

          initial_score = evaluate(@visible_state)

          return empty_result(initial_score) unless
            @visible_state["status"] == "started"

          return empty_result(initial_score) unless
            @visible_state["current_player_id"].to_s == @player_id

          root_actions = available_actions(@visible_state)

          Rails.logger.info(
            "[OpponentEngine] Root actions: " \
            "#{root_actions.group_by { |action| action["type"] }.transform_values(&:size)}"
          )

          Rails.logger.info(
            "[OpponentEngine] Root moves: " \
            "#{root_actions.select { |action| action["type"] == "move" }.inspect}"
          )

          frontier = [
            Node.new(
              visible_state: @visible_state,
              actions: [],
              steps: [],
              score: initial_score,
              terminal: false
            )
          ]

          completed = []
          expanded_nodes = 0
          frontier_expanded = false

          @depth.times do
            candidates = []

            frontier.each do |node|
              node_actions = available_actions(node.visible_state)

              node_actions.each do |action|
                # Если штаб может безопасно подготовить уничтожение цели,
                # сначала рассматриваем его дальнюю атаку.
                next if defer_technique_attack_for_headquarters_setup?(
                  node,
                  action,
                  node_actions
                )

                # Не завершаем ход, если доступна безопасная
                # добивающая атака собственной техники.
                next if action["type"] == "end_turn" &&
                        safe_lethal_attack_available?(node, node_actions)

                simulation = simulate(
                  node.visible_state,
                  action
                )

                unless simulation.success?
                  if node.actions.empty? && action["type"] == "move"
                    Rails.logger.warn(
                      "[OpponentEngine] Move simulation FAILED: " \
                      "#{action["payload"].inspect}, " \
                      "error: #{simulation.error}"
                    )
                  end

                  next
                end

                # Если штаб и техника бьют одну цель, штаб стреляет первым.
                next if headquarters_after_technique_on_same_target?(
                  node,
                  action
                )

                action_copy = action.deep_dup
                expected_state = simulation.visible_state.deep_dup

                actions = node.actions + [action_copy]

                step = Step.new(
                  action: action_copy.deep_dup,
                  expected_visible_state: expected_state.deep_dup
                )

                steps = node.steps + [step]

                tactical_bonus = tactical_sequence_bonus(
                  actions,
                  steps
                )

                # Штраф применяется только при завершении хода.
                # До этого момента техника ещё может успеть атаковать.
                idle_penalty =
                  if action["type"] == "end_turn"
                    idle_advance_penalty(actions, steps)
                  else
                    0.0
                  end

                child_score =
                  evaluate(expected_state) +
                  tactical_bonus -
                  idle_penalty

                if node.actions.empty?
                  breakdown = evaluate_breakdown(expected_state)

                  breakdown[:counterattack_exploitation_bonus] =
                    tactical_bonus

                  breakdown[:idle_advance_penalty] =
                    idle_penalty

                  Rails.logger.info(
                    "[OpponentEngine] Root candidate: " \
                    "type=#{action["type"]}, " \
                    "payload=#{action["payload"].inspect}, " \
                    "score=#{child_score.round(2)}, " \
                    "breakdown=#{breakdown.transform_values { |value| value.round(2) }.inspect}"
                  )
                end

                expanded_nodes += 1

                child = Node.new(
                  visible_state: expected_state,
                  actions: actions,
                  steps: steps,
                  score: child_score,
                  terminal: terminal_action?(
                    action,
                    expected_state
                  )
                )

                if child.terminal
                  completed << child
                else
                  candidates << child
                end
              end
            end

            if candidates.empty?
              frontier_expanded = true
              break
            end

            frontier = rank(candidates).first(@width)
          end

          # Узел без end_turn оценён посреди хода.
          # Достраиваем такие узлы до завершения хода.
          unless frontier_expanded
            frontier.each do |node|
              next if node.actions.empty?

              finished = finish_turn(node)
              next unless finished

              expanded_nodes += 1
              completed << finished
            end
          end

          best_node = completed
            .reject { |node| node.actions.empty? }
            .max_by do |node|
              [
                node.score,
                -node.actions.length
              ]
            end

          best_node ||= frontier
            .reject { |node| node.actions.empty? }
            .max_by do |node|
              [
                node.score,
                -node.actions.length
              ]
            end

          Rails.logger.info(
            "[OpponentEngine] Selected plan: #{best_node&.actions.inspect}"
          )

          Rails.logger.info(
            "[OpponentEngine] Selected plan diagnostics: " \
            "score=#{best_node&.score || initial_score}, " \
            "score_delta=#{((best_node&.score || initial_score) - initial_score).round(2)}, " \
            "actions=#{plan_action_counts(best_node)}, " \
            "attackers=#{plan_attacker_types(best_node)}"
          )

          elapsed_ms = (
            Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
          ) * 1000

          phase_summary = @phase_timings.map do |name, stats|
            average_ms = stats[:total_ms] / stats[:calls]

            "#{name}=#{stats[:calls]} calls, " \
              "total=#{stats[:total_ms].round(1)}ms, " \
              "avg=#{average_ms.round(2)}ms, " \
              "max=#{stats[:max_ms].round(1)}ms"
          end.join(" | ")

          strategic_summary = @strategic_component_timings
            .sort_by { |name, _stats| name.to_s }
            .map do |name, stats|
              average_ms = stats[:total_ms] / stats[:calls]

              "#{name}=#{stats[:calls]} calls, " \
                "total=#{stats[:total_ms].round(1)}ms, " \
                "avg=#{average_ms.round(2)}ms, " \
                "max=#{stats[:max_ms].round(1)}ms"
            end
            .join(" | ")

          Rails.logger.info(
            "[OpponentEngine] Strategic profile: #{strategic_summary}"
          )

          Rails.logger.info(
            "[OpponentEngine] Search profile: #{phase_summary}"
          )

          Rails.logger.info(
            "[OpponentEngine] Search completed: " \
            "depth=#{@depth}, " \
            "width=#{@width}, " \
            "expanded_nodes=#{expanded_nodes}, " \
            "elapsed_ms=#{elapsed_ms.round(1)}, " \
            "selected_actions=#{best_node&.actions&.length || 0}"
          )

          Result.new(
            actions: best_node ? best_node.actions : [],
            steps: best_node ? best_node.steps : [],
            score: best_node ? best_node.score : initial_score,
            expanded_nodes: expanded_nodes
          )
        end

        private

        # ------------------------------------------------------------
        # Порядок совместной атаки: штаб первым
        # ------------------------------------------------------------

        # ------------------------------------------------------------
        # Дальняя атака штаба перед добиванием техникой
        # ------------------------------------------------------------

        def defer_technique_attack_for_headquarters_setup?(
          node,
          action,
          node_actions
        )
          return false unless action["type"] == "attack"

          attacker_position = action.dig("payload", "attacker")
          target_position = action.dig("payload", "target")

          return false unless
            attacker_position.is_a?(Array) &&
            attacker_position.length == 2 &&
            target_position.is_a?(Array) &&
            target_position.length == 2

          attacker = node.visible_state.dig(
            "field",
            attacker_position[0],
            attacker_position[1]
          )

          target = node.visible_state.dig(
            "field",
            target_position[0],
            target_position[1]
          )

          return false unless attacker&.dig("type") == "technique"
          return false unless attacker["player_id"].to_s == @player_id

          return false unless target&.dig("type") == "technique"
          return false if target["player_id"].to_s == @player_id

          # Если цель уже использовала контратаку,
          # это не рассматриваемый сценарий.
          return false if target["has_counterattacked"]

          headquarters_position = own_headquarters_position
          return false unless headquarters_position

          # Штаб должен атаковать именно эту цель.
          # И обязательно дальней атакой.
          return false if GameEngine::Rules::Position.adjacent?(
            headquarters_position,
            target_position
          )

          headquarters_action = node_actions.find do |candidate|
            candidate["type"] == "attack" &&
              candidate.dig("payload", "attacker") == headquarters_position &&
              candidate.dig("payload", "target") == target_position
          end

          return false unless headquarters_action

          # Симулируем дальнюю атаку штаба.
          headquarters_simulation = simulate(
            node.visible_state,
            headquarters_action
          )

          return false unless headquarters_simulation.success?

          state_after_headquarters = headquarters_simulation.visible_state

          target_after_headquarters = state_after_headquarters.dig(
            "field",
            target_position[0],
            target_position[1]
          )

          attacker_after_headquarters = state_after_headquarters.dig(
            "field",
            attacker_position[0],
            attacker_position[1]
          )

          # Цель должна пережить выстрел штаба, но получить урон.
          return false unless target_after_headquarters
          return false unless target_after_headquarters["type"] == "technique"
          return false unless
            target_after_headquarters["hp"].to_i < target["hp"].to_i

          # Дальняя атака штаба не должна расходовать контратаку цели.
          return false if target_after_headquarters["has_counterattacked"]

          # Наша техника должна остаться на месте.
          return false unless attacker_after_headquarters
          return false unless attacker_after_headquarters["type"] == "technique"

          # После выстрела штаба ищем атаку той же техникой
          # по той же цели.
          follow_up_actions = available_actions(state_after_headquarters)

          follow_up_action = follow_up_actions.find do |candidate|
            candidate["type"] == "attack" &&
              candidate.dig("payload", "attacker") == attacker_position &&
              candidate.dig("payload", "target") == target_position
          end

          return false unless follow_up_action

          # Проверяем добивание через настоящий GameEngine.
          follow_up_simulation = simulate(
            state_after_headquarters,
            follow_up_action
          )

          return false unless follow_up_simulation.success?

          final_state = follow_up_simulation.visible_state

          # Цель должна быть уничтожена.
          return false if final_state.dig(
            "field",
            target_position[0],
            target_position[1]
          )

          final_attacker = final_state.dig(
            "field",
            attacker_position[0],
            attacker_position[1]
          )

          return false unless final_attacker

          # Техника не должна получить ответный урон.
          return false unless
            final_attacker["hp"].to_i == attacker["hp"].to_i

          # Дополнительная проверка: в бою не должно быть события контратаки.
          counterattack_fired = follow_up_simulation.events.any? do |event|
            (event[:type] || event["type"]).to_s == "counterattack_fired"
          end

          return false if counterattack_fired

          true
        end

        def headquarters_after_technique_on_same_target?(node, action)
          return false unless action["type"] == "attack"

          attacker = action.dig("payload", "attacker")
          target = action.dig("payload", "target")

          return false unless attacker.is_a?(Array) && target.is_a?(Array)
          return false unless attacker == own_headquarters_position

          # Штаб, стоящий вплотную к цели, получает ответ как обычная
          # техника: там выбор порядка остаётся за оценкой состояния.
          return false if GameEngine::Rules::Position.adjacent?(
            attacker,
            target
          )

          node.actions.any? do |previous|
            previous["type"] == "attack" &&
              previous.dig("payload", "target") == target &&
              previous.dig("payload", "attacker") != attacker
          end
        end

        def own_headquarters_position
          return @own_headquarters_position if
            defined?(@own_headquarters_position)

          @own_headquarters_position = find_own_headquarters_position
        end

        def find_own_headquarters_position
          @visible_state.fetch("field").each_with_index do |row, row_index|
            row.each_with_index do |object, column_index|
              next unless object
              next unless object["type"] == "headquarters"
              next unless object["player_id"].to_s == @player_id

              return [row_index, column_index]
            end
          end

          nil
        end

        # ------------------------------------------------------------
        # Завершение хода
        # ------------------------------------------------------------

        # Проверяет, есть ли доступная атака собственной техники,
        # которая уничтожает вражескую технику без ответного урона.
        def safe_lethal_attack_available?(node, actions)
          actions.any? do |candidate|
            next false unless candidate["type"] == "attack"

            attacker_position = candidate.dig("payload", "attacker")
            target_position = candidate.dig("payload", "target")

            next false unless attacker_position.is_a?(Array)
            next false unless attacker_position.length == 2
            next false unless target_position.is_a?(Array)
            next false unless target_position.length == 2

            attacker = node.visible_state.dig(
              "field",
              attacker_position[0],
              attacker_position[1]
            )

            target = node.visible_state.dig(
              "field",
              target_position[0],
              target_position[1]
            )

            # Учитываем только атаки собственной техники
            # по вражеской технике.
            next false unless attacker&.dig("type") == "technique"
            next false unless attacker["player_id"].to_s == @player_id

            next false unless target&.dig("type") == "technique"
            next false if target["player_id"].to_s == @player_id

            simulation = simulate(
              node.visible_state,
              candidate
            )

            next false unless simulation.success?

            final_state = simulation.visible_state

            # Цель должна быть уничтожена.
            target_after = final_state.dig(
              "field",
              target_position[0],
              target_position[1]
            )

            next false unless target_after.nil?

            # Атакующая техника должна выжить и не потерять HP.
            attacker_after = final_state.dig(
              "field",
              attacker_position[0],
              attacker_position[1]
            )

            next false unless attacker_after
            next false unless attacker_after["type"] == "technique"
            next false unless attacker_after["player_id"].to_s == @player_id

            next false unless
              attacker_after["hp"].to_i >= attacker["hp"].to_i

            # Дополнительно убеждаемся, что симуляция
            # не зарегистрировала ответную атаку.
            counterattack_fired = simulation.events.any? do |event|
              (event[:type] || event["type"]).to_s == "counterattack_fired"
            end

            next false if counterattack_fired

            true
          end
        end

        def finish_turn(node)
          node_actions = available_actions(node.visible_state)

          # Последний шаг Beam Search тоже не должен обходить
          # проверку безопасной добивающей атаки.
          return nil if safe_lethal_attack_available?(node, node_actions)

          action = { "type" => "end_turn", "payload" => {} }

          simulation = simulate(node.visible_state, action)
          return nil unless simulation.success?

          expected_state = simulation.visible_state.deep_dup

          step = Step.new(
            action: action.deep_dup,
            expected_visible_state: expected_state.deep_dup
          )

          actions = node.actions + [action.deep_dup]
          steps = node.steps + [step]

          idle_penalty = idle_advance_penalty(actions, steps)

          Node.new(
            visible_state: expected_state,
            actions: actions,
            steps: steps,
            score: evaluate(expected_state) +
              tactical_sequence_bonus(
                node.actions,
                node.steps
              ) -
              idle_penalty,
            terminal: true
          )
        end

        # ------------------------------------------------------------
        # Безопасное освобождение клеток плацдарма
        # ------------------------------------------------------------

        # Учитываем только перемещения техники, которая начинала
        # движение с клетки, соседней с собственным штабом.
        #
        # Продвижение к штабу противника без последующей атаки
        # получает штраф.
        #
        # Вертикальное перемещение и отход назад не штрафуются.
        # Атака после последнего перемещения снимает штраф.
        def idle_advance_penalty(actions, steps)
          enemy_headquarters = enemy_headquarters_position
          return 0.0 unless enemy_headquarters

          tracks = []

          actions.each_with_index do |action, index|
            payload = action["payload"] || {}

            previous_state =
              if index.zero?
                @visible_state
              else
                steps[index - 1]&.expected_visible_state
              end

            next unless previous_state

            case action["type"]
            when "move"
              from = payload["from"]
              to = payload["to"]

              next unless from.is_a?(Array) && to.is_a?(Array)

              technique = previous_state.dig(
                "field",
                from[0],
                from[1]
              )

              next unless technique
              next unless technique["type"] == "technique"
              next unless technique["player_id"].to_s == @player_id

              # Учитываем только освобождение исходной клетки плацдарма.
              existing_track = tracks.find do |track|
                track[:to] == from
              end

              if existing_track
                existing_track[:to] = to.dup
                existing_track[:last_move_index] = index
                existing_track[:attacked_after_move] = false
              elsif @root_deployment_positions.include?(from)
                tracks << {
                  from: from.dup,
                  to: to.dup,
                  last_move_index: index,
                  attacked_after_move: false
                }
              end

            when "attack"
              attacker = payload["attacker"]

              next unless attacker.is_a?(Array)

              track = tracks.find do |item|
                item[:to] == attacker &&
                  index > item[:last_move_index]
              end

              next unless track

              attacker_object = previous_state.dig(
                "field",
                attacker[0],
                attacker[1]
              )

              next unless attacker_object
              next unless attacker_object["type"] == "technique"
              next unless attacker_object["player_id"].to_s == @player_id

              track[:attacked_after_move] = true
            end
          end

          idle_advances = tracks.count do |track|
            source_distance = (
              track[:from][1] - enemy_headquarters[1]
            ).abs

            destination_distance = (
              track[:to][1] - enemy_headquarters[1]
            ).abs

            destination_distance < source_distance &&
              !track[:attacked_after_move]
          end

          return 0.0 if idle_advances.zero?

          deck_count = @visible_state
            .dig("players", @player_id, "deck_count")
            .to_f

          patience = [
            deck_count / 12.0,
            1.0
          ].min

          patience = [
            patience,
            IDLE_MIN_PATIENCE
          ].max

          idle_advances *
            IDLE_ADVANCE_PENALTY *
            patience
        end

        def enemy_headquarters_position
          @visible_state.fetch("field").each_with_index do |row, row_index|
            row.each_with_index do |object, column_index|
              next unless object
              next unless object["type"] == "headquarters"
              next if object["player_id"].to_s == @player_id

              return [row_index, column_index]
            end
          end

          nil
        end

        # --------------------------------------------------------------
        # Приоритет атаки по технике с использованной контратакой
        # --------------------------------------------------------------

        def counterattack_exploitation_bonus(actions, steps)
          actions.each_with_index.sum do |action, index|
            previous_state =
              if index.zero?
                @visible_state
              else
                steps[index - 1].expected_visible_state
              end

            counterattack_exploitation_bonus_for_action(
              visible_state: previous_state,
              action: action,
              expected_visible_state: steps[index].expected_visible_state
            )
          end
        end

        def tactical_sequence_bonus(actions, steps)
          counterattack_exploitation_bonus(actions, steps) +
            safe_headquarters_follow_up_bonus(actions, steps) +
            safe_headquarters_raid_bonus(actions, steps)
        end

        def safe_headquarters_raid_bonus(actions, steps)
          return 0.0 if actions.length < 2

          actions.each_cons(2).with_index do |(move_action, attack_action), index|
            next unless move_action["type"] == "move"
            next unless attack_action["type"] == "attack"

            from = move_action.dig("payload", "from")
            to = move_action.dig("payload", "to")

            attacker_position = attack_action.dig("payload", "attacker")
            target_position = attack_action.dig("payload", "target")

            # Атаковать должен тот же танк, который только что переместился.
            next unless to == attacker_position

            next unless from.is_a?(Array) && from.length == 2
            next unless to.is_a?(Array) && to.length == 2
            next unless target_position.is_a?(Array) && target_position.length == 2

            next unless steps[index] && steps[index + 1]

            previous_state =
              index.zero? ?
                @visible_state :
                steps[index - 1].expected_visible_state

            state_after_move = steps[index].expected_visible_state
            state_after_attack = steps[index + 1].expected_visible_state

            attacker_before = previous_state.dig(
              "field",
              from[0],
              from[1]
            )

            attacker_after_move = state_after_move.dig(
              "field",
              to[0],
              to[1]
            )

            headquarters_before = state_after_move.dig(
              "field",
              target_position[0],
              target_position[1]
            )

            headquarters_after = state_after_attack.dig(
              "field",
              target_position[0],
              target_position[1]
            )

            # Перемещаться и атаковать должна наша техника.
            next unless attacker_before&.dig("type") == "technique"
            next unless attacker_before["player_id"].to_s == @player_id

            # Целью должен быть именно вражеский штаб.
            next unless headquarters_before&.dig("type") == "headquarters"
            next if headquarters_before["player_id"].to_s == @player_id

            # Техника должна пережить перемещение и атаку.
            next unless attacker_after_move
            next unless attacker_after_move["type"] == "technique"

            attacker_after_attack = state_after_attack.dig(
              "field",
              to[0],
              to[1]
            )

            next unless attacker_after_attack
            next unless attacker_after_attack["type"] == "technique"

            # Атака должна действительно нанести урон штабу.
            next unless headquarters_after
            next unless headquarters_after["type"] == "headquarters"

            damage =
              headquarters_before["hp"].to_i -
              headquarters_after["hp"].to_i

            next unless damage.positive?

            # Не поощряем рискованную атаку, если техника потеряла HP.
            next unless
              attacker_after_attack["hp"].to_i ==
                attacker_before["hp"].to_i

            bonus = SAFE_HEADQUARTERS_RAID_BONUS

            # Если в состоянии явно указано максимальное HP штаба,
            # усиливаем бонус при критически низком здоровье.
            max_hp = headquarters_before["max_hp"].to_i
            current_hp = headquarters_before["hp"].to_i

            if max_hp.positive? &&
                current_hp.to_f / max_hp <= CRITICAL_HEADQUARTERS_HP_RATIO
              bonus *= CRITICAL_HEADQUARTERS_RAID_MULTIPLIER
            end

            return bonus
          end

          0.0
        end

        def safe_headquarters_follow_up_bonus(actions, steps)
          return 0.0 if actions.length < 2

          actions.each_cons(2).with_index do |(
            headquarters_action,
            technique_action
          ), index|
            next unless headquarters_action["type"] == "attack"
            next unless technique_action["type"] == "attack"

            headquarters_position =
              headquarters_action.dig("payload", "attacker")

            target_position =
              headquarters_action.dig("payload", "target")

            technique_position =
              technique_action.dig("payload", "attacker")

            next unless headquarters_position == own_headquarters_position
            next unless technique_action.dig("payload", "target") == target_position

            next if GameEngine::Rules::Position.adjacent?(
              headquarters_position,
              target_position
            )

            next unless steps[index] && steps[index + 1]

            state_after_headquarters =
              steps[index].expected_visible_state

            state_after_technique =
              steps[index + 1].expected_visible_state

            cache = (
              @safe_headquarters_follow_up_bonus_cache ||= {}
            )

            cache_key = [
              index,
              target_position,
              technique_position,
              state_after_headquarters.hash
            ]

            next if cache.key?(cache_key) && !cache[cache_key]

            unless cache.key?(cache_key)
              cache[cache_key] = safe_headquarters_follow_up_sequence?(
                headquarters_position: headquarters_position,
                target_position: target_position,
                technique_position: technique_position,
                headquarters_action: headquarters_action,
                technique_action: technique_action,
                state_after_headquarters: state_after_headquarters,
                state_after_technique: state_after_technique,
                previous_state: (
                  index.zero? ?
                    @visible_state :
                    steps[index - 1].expected_visible_state
                )
              )
            end

            return SAFE_HEADQUARTERS_FOLLOW_UP_BONUS if cache[cache_key]
          end

          0.0
        end

        def safe_headquarters_follow_up_sequence?(
          headquarters_position:,
          target_position:,
          technique_position:,
          headquarters_action:,
          technique_action:,
          state_after_headquarters:,
          state_after_technique:,
          previous_state:
        )
          target_before = previous_state.dig(
            "field",
            target_position[0],
            target_position[1]
          )

          target_after_headquarters = state_after_headquarters.dig(
            "field",
            target_position[0],
            target_position[1]
          )

          # Цель должна быть вражеской техникой.
          return false unless target_before&.dig("type") == "technique"
          return false if target_before["player_id"].to_s == @player_id
          return false if target_before["has_counterattacked"]

          # Штаб должен ослабить цель, но не уничтожить её.
          return false unless target_after_headquarters
          return false unless target_after_headquarters["type"] == "technique"
          return false unless
            target_after_headquarters["hp"].to_i < target_before["hp"].to_i

          # Дальняя атака штаба не должна вызывать контратаку.
          return false if target_after_headquarters["has_counterattacked"]

          headquarters_before = previous_state.dig(
            "field",
            headquarters_position[0],
            headquarters_position[1]
          )

          headquarters_after = state_after_headquarters.dig(
            "field",
            headquarters_position[0],
            headquarters_position[1]
          )

          return false unless headquarters_before && headquarters_after
          return false unless
            headquarters_before["hp"].to_i == headquarters_after["hp"].to_i

          # После выстрела штаба наша техника должна оставаться на поле.
          technique_before = state_after_headquarters.dig(
            "field",
            technique_position[0],
            technique_position[1]
          )

          technique_after = state_after_technique.dig(
            "field",
            technique_position[0],
            technique_position[1]
          )

          return false unless technique_before&.dig("type") == "technique"
          return false unless technique_before["player_id"].to_s == @player_id
          return false unless technique_after
          return false unless technique_after["type"] == "technique"

          # Техника должна уничтожить именно эту цель.
          return false if state_after_technique.dig(
            "field",
            target_position[0],
            target_position[1]
          )

          # Проверяем последующую атаку настоящим GameEngine.
          simulation = simulate(
            state_after_headquarters,
            technique_action
          )

          return false unless simulation.success?

          final_state = simulation.visible_state

          return false if final_state.dig(
            "field",
            target_position[0],
            target_position[1]
          )

          final_technique = final_state.dig(
            "field",
            technique_position[0],
            technique_position[1]
          )

          return false unless final_technique
          return false unless
            final_technique["hp"].to_i == technique_before["hp"].to_i

          # Никакой контратаки во время добивания.
          counterattack_fired = simulation.events.any? do |event|
            (event[:type] || event["type"]).to_s == "counterattack_fired"
          end

          return false if counterattack_fired

          true
        end

        def counterattack_exploitation_bonus_for_action(
          visible_state:,
          action:,
          expected_visible_state:
        )
          return 0.0 unless action["type"] == "attack"

          target_position = action.dig("payload", "target")

          return 0.0 unless
            target_position.is_a?(Array) &&
            target_position.length == 2

          row, column = target_position

          target = visible_state.dig("field", row, column)

          return 0.0 unless target
          return 0.0 unless target["type"] == "technique"
          return 0.0 unless target["player_id"].to_s != @player_id
          return 0.0 unless target["has_counterattacked"]

          # Штаб бьёт издалека и ответа не получает, поэтому его выстрел
          # по цели с потраченной контратакой не должен награждаться.
          attacker_position = action.dig("payload", "attacker")

          if attacker_position.is_a?(Array)
            attacker = visible_state.dig(
              "field",
              attacker_position[0],
              attacker_position[1]
            )

            return 0.0 if attacker && attacker["type"] == "headquarters"
          end

          target_after =
            expected_visible_state.dig("field", row, column)

          hp_after = target_after ? target_after["hp"].to_i : 0

          damage = [
            target["hp"].to_i - hp_after,
            0
          ].max

          damage * COUNTERATTACK_SPENT_DAMAGE_BONUS
        end

        # --------------------------------------------------------------
        # Разделение веток поиска
        # --------------------------------------------------------------

        def first_action_category(node)
          action = node.actions.first
          return "empty" unless action

          payload = action["payload"] || {}

          case action["type"]
          when "play_card"
            card_id = payload["card_id"].to_s
            card_type = @root_card_types[card_id] || "unknown"

            "play_card:#{card_type}:#{card_id}"

          when "move"
            from = Array(payload["from"]).join(",")

            if @root_deployment_positions.include?(payload["from"]) &&
                !@root_deployment_positions.include?(payload["to"])
              "move:free_deployment:#{from}"
            else
              "move:#{from}"
            end

          when "attack"
            attacker = Array(payload["attacker"]).join(",")
            target = Array(payload["target"]).join(",")

            "attack:#{attacker}:#{target}"

          else
            action["type"]
          end
        end

        def second_action_category(node)
          action = node.actions[1]
          return "single_action" unless action

          payload = action["payload"] || {}

          case action["type"]
          when "attack"
            attacker = Array(payload["attacker"]).join(",")
            target = Array(payload["target"]).join(",")

            "attack:#{attacker}:#{target}"

          when "move"
            from = Array(payload["from"]).join(",")
            to = Array(payload["to"]).join(",")

            "move:#{from}:#{to}"

          when "play_card"
            card_id = payload["card_id"].to_s
            card_type = @root_card_types[card_id] || "unknown"

            targets =
              payload["targets"] ||
              [payload["row"], payload["column"]]

            "play_card:#{card_type}:#{card_id}:#{targets.inspect}"

          else
            action["type"]
          end
        end

        def root_deployment_positions
          @visible_state.fetch("field").each_with_index do |row, row_index|
            row.each_with_index do |object, column_index|
              next unless object
              next unless object["type"] == "headquarters"
              next unless object["player_id"].to_s == @player_id

              return GameEngine::Rules::Position.neighbors(
                [row_index, column_index]
              )
            end
          end

          []
        end

        # --------------------------------------------------------------
        # Генерация допустимых действий
        # --------------------------------------------------------------

        def available_actions(visible_state)
          measure_phase(:available_actions) do
            DecisionProviders::ActionOptions.call(visible_state)
          end
        end

        # --------------------------------------------------------------
        # Симуляция действия
        # --------------------------------------------------------------

        def simulate(visible_state, action)
          measure_phase(:simulate) do
            StateSimulator.call(
              visible_state: visible_state,
              player_id: @player_id,
              action: action,
              current_time: @current_time
            )
          end
        end

        # --------------------------------------------------------------
        # Стратегическая оценка
        # --------------------------------------------------------------

        def evaluate(visible_state)
          measure_phase(:evaluate) do
            StrategicEvaluator.call(
              visible_state: visible_state,
              player_id: @player_id,
              profile: @strategic_component_timings
            )
          end
        end

        def evaluate_breakdown(visible_state)
          measure_phase(:evaluate_breakdown) do
            StrategicEvaluator.new(
              visible_state: visible_state,
              player_id: @player_id,
              profile: @strategic_component_timings,
              profile_scope: :breakdown
            ).score_breakdown
          end
        end

        # --------------------------------------------------------------
        # Профилирование
        # --------------------------------------------------------------

        def measure_phase(name)
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          yield
        ensure
          elapsed_ms = (
            Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
          ) * 1000

          stats = @phase_timings[name]

          stats[:calls] += 1
          stats[:total_ms] += elapsed_ms
          stats[:max_ms] = [stats[:max_ms], elapsed_ms].max
        end

        # --------------------------------------------------------------
        # Завершение ветки
        # --------------------------------------------------------------

        def terminal_action?(action, visible_state)
          action["type"] == "end_turn" ||
            visible_state["status"] != "started" ||
            visible_state["current_player_id"].to_s != @player_id
        end

        # --------------------------------------------------------------
        # Beam Search
        # --------------------------------------------------------------

        def rank(nodes)
          ranked_nodes = nodes.sort_by do |node|
            [
              -node.score,
              node.actions.length
            ]
          end

          category_representatives =
            ranked_nodes
              .group_by do |node|
                [
                  first_action_category(node),
                  second_action_category(node)
                ]
              end
              .values
              .map(&:first)

          action_type_representatives =
            ranked_nodes
              .group_by { |node| node.actions.first&.dig("type") }
              .values
              .map(&:first)

          actor_representatives =
            ranked_nodes
              .group_by { |node| first_action_actor_category(node) }
              .values
              .map(&:first)

          selected = []

          [
            action_type_representatives,
            actor_representatives,
            category_representatives,
            ranked_nodes
          ].each do |collection|
            collection.each do |node|
              selected << node unless selected.any? { |item| item.equal?(node) }

              break if selected.length >= @width
            end

            break if selected.length >= @width
          end

          selected
        end

        def first_action_actor_category(node)
          action = node.actions.first
          return "empty" unless action

          payload = action["payload"] || {}

          case action["type"]
          when "attack"
            attacker = Array(payload["attacker"]).join(",")
            target = Array(payload["target"]).join(",")

            if payload["attacker"] == own_headquarters_position
              "attack:headquarters:#{target}"
            else
              "attack:#{attacker}"
            end

          when "move"
            "move:#{Array(payload["from"]).join(",")}"

          when "play_card"
            card_id = payload["card_id"].to_s
            card_type = @root_card_types[card_id] || "unknown"

            "play_card:#{card_type}:#{card_id}"

          else
            action["type"]
          end
        end

        def plan_action_counts(node)
          Array(node&.actions).map { |action| action["type"] }.tally
        end

        def plan_attacker_types(node)
          Array(node&.steps).filter_map do |step|
            action = step.action
            next unless action["type"] == "attack"

            position = action.dig("payload", "attacker")
            attacker = step.expected_visible_state.dig(
              "field",
              position[0],
              position[1]
            )

            attacker ? attacker["type"] : "destroyed"
          end.tally
        end

        def empty_result(score)
          Result.new(
            actions: [],
            steps: [],
            score: score,
            expanded_nodes: 0
          )
        end
      end
    end
  end
end
