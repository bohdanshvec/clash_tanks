
module DecisionProviders
  module OpponentEngine
    module Planning
      class TacticalPlanner
        DEFAULT_DEPTH = 5
        DEFAULT_WIDTH = 10

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

          @depth.times do
            candidates = []

            frontier.each do |node|
              node_actions = available_actions(node.visible_state)

              node_actions.each do |action|
                simulation = simulate(
                  node.visible_state,
                  action
                )

                if node.actions.empty? && action["type"] == "move"
                  if simulation.success?
                    Rails.logger.info(
                      "[OpponentEngine] Move simulation SUCCESS: " \
                      "#{action["payload"].inspect}, " \
                      "score: #{evaluate(simulation.visible_state)}"
                    )
                  else
                    Rails.logger.warn(
                      "[OpponentEngine] Move simulation FAILED: " \
                      "#{action["payload"].inspect}, " \
                      "error: #{simulation.error}"
                    )
                  end
                end

                next unless simulation.success?

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
                  score: evaluate(expected_state),
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

            break if candidates.empty?

            frontier = rank(candidates).first(@width)
          end

          best_node = (completed + frontier)
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

          Result.new(
            actions: best_node ? best_node.actions : [],
            steps: best_node ? best_node.steps : [],
            score: best_node ? best_node.score : initial_score,
            expanded_nodes: expanded_nodes
          )
        end

        private

        def first_action_category(node)
          action = node.actions.first
          return "empty" unless action

          payload = action["payload"] || {}

          case action["type"]
          when "play_card"
            card_id = payload["card_id"].to_s
            card_type = @root_card_types[card_id] || "unknown"

            "play_card:#{card_type}"

          when "move"
            if @root_deployment_positions.include?(payload["from"]) &&
                !@root_deployment_positions.include?(payload["to"])
              "move:free_deployment"
            else
              "move"
            end

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
          DecisionProviders::ActionOptions.call(visible_state)
        end

        # --------------------------------------------------------------
        # Симуляция действия
        # --------------------------------------------------------------

        def simulate(visible_state, action)
          StateSimulator.call(
            visible_state: visible_state,
            player_id: @player_id,
            action: action,
            current_time: @current_time
          )
        end

        # --------------------------------------------------------------
        # Стратегическая оценка
        # --------------------------------------------------------------

        def evaluate(visible_state)
          StrategicEvaluator.call(
            visible_state: visible_state,
            player_id: @player_id
          )
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
              .first(@width)

          representative_ids =
            category_representatives.each_with_object({}) do |node, result|
              result[node.object_id] = true
            end

          category_representatives +
            ranked_nodes.reject do |node|
              representative_ids.key?(node.object_id)
            end
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
