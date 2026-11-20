
module DecisionProviders
  module OpponentEngine
    module Planning
      class TacticalPlanner
        DEFAULT_DEPTH = 7
        DEFAULT_WIDTH = 20

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

                child_score = evaluate(simulation.visible_state)

                if node.actions.empty?
                  breakdown = evaluate_breakdown(
                    simulation.visible_state
                  )

                  Rails.logger.info(
                    "[OpponentEngine] Root candidate: " \
                    "type=#{action["type"]}, " \
                    "payload=#{action["payload"].inspect}, " \
                    "score=#{child_score.round(2)}, " \
                    "breakdown=#{breakdown.transform_values { |value| value.round(2) }.inspect}"
                  )
                end

                expanded_nodes += 1

                action_copy = action.deep_dup
                expected_state = simulation.visible_state.deep_dup

                actions = node.actions + [action_copy]

                step = Step.new(
                  action: action_copy.deep_dup,
                  expected_visible_state: expected_state.deep_dup
                )

                child = Node.new(
                  visible_state: expected_state,
                  actions: actions,
                  steps: node.steps + [step],
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

          # Узел без end_turn оценён «посреди хода». Его нельзя сравнивать
          # с завершённым ходом: у него нет пополнения топлива противника,
          # штрафов и бонусов конца хода, поэтому он выглядит лучше.
          # Достраиваем такие узлы до end_turn и выбираем только среди
          # завершённых ходов.
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

        # Достраивает незавершённый узел действием end_turn.
        def finish_turn(node)
          action = { "type" => "end_turn", "payload" => {} }

          simulation = simulate(node.visible_state, action)
          return nil unless simulation.success?

          expected_state = simulation.visible_state.deep_dup

          step = Step.new(
            action: action.deep_dup,
            expected_visible_state: expected_state.deep_dup
          )

          Node.new(
            visible_state: expected_state,
            actions: node.actions + [action.deep_dup],
            steps: node.steps + [step],
            score: evaluate(expected_state),
            terminal: true
          )
        end

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

            # Для одного атакующего цели могут иметь принципиально разные
            # продолжения: например, штаб может давить вражеский штаб или
            # начать последовательную атаку по технике вместе с танком.
            # Нельзя оставлять в beam только одну из таких веток.
            "attack:#{attacker}:#{target}"

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
              player_id: @player_id
            )
          end
        end

        def evaluate_breakdown(visible_state)
          measure_phase(:evaluate_breakdown) do
            StrategicEvaluator.new(
              visible_state: visible_state,
              player_id: @player_id
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
              .group_by { |node| first_action_category(node) }
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
            "attack:#{Array(payload["attacker"]).join(",")}"

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
