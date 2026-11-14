module DecisionProviders
  module OpponentEngine
    module Planning
      class ForceCoordinationEvaluator

        Analysis = Data.define(
          :best_single_gain,
          :best_combined_gain
        ) do
          def coordination_bonus
            [
              best_combined_gain - best_single_gain,
              0
            ].max
          end
        end

        MAX_TECHNIQUES = 3
        MAX_ATTACK_POSITIONS = 2

        def self.call(
          visible_state:,
          player_id:,
          target_position:,
          attackers:,
          material_scorer:
        )
          new(
            visible_state:,
            player_id:,
            target_position:,
            attackers:,
            material_scorer:
          ).call
        end

        def self.analyze(
          visible_state:,
          player_id:,
          target_position:,
          attackers:,
          material_scorer:
        )
          new(
            visible_state:,
            player_id:,
            target_position:,
            attackers:,
            material_scorer:
          ).analyze
        end

        def initialize(
          visible_state:,
          player_id:,
          target_position:,
          attackers:,
          material_scorer:
        )
          @visible_state = visible_state
          @player_id = player_id.to_s
          @opponent_id = visible_state["players"].keys.find do |id|
            id.to_s != @player_id
          end.to_s
          @target_position = target_position
          @attackers = attackers
          @material_scorer = material_scorer
        end

        def call
          analyze.coordination_bonus
        end

        def analyze
          techniques = @attackers
            .sort_by { |attacker| -attacker[:firepower] }
            .first(MAX_TECHNIQUES)

          return Analysis.new(0, 0) if techniques.length < 2

          @candidates = techniques.map do |attacker|
            {
              kind: :technique,
              key: [:technique, attacker[:position]],
              origin: attacker[:position],
              destinations: attacker[:attack_positions].first(MAX_ATTACK_POSITIONS)
            }
          end

          add_headquarters_candidate

          initial_state = simulation_state(@visible_state)
          @initial_score = state_score(initial_state)

          @best_single_gain = 0
          @best_combined_gain = 0

          explore(
            state: initial_state,
            used_keys: [],
            technique_count: 0
          )

          Analysis.new(
            @best_single_gain,
            @best_combined_gain
          )
        end

        private

        # ------------------------------------------------------------
        # Возможные участники атаки
        # ------------------------------------------------------------

        def add_headquarters_candidate
          headquarters_position = headquarters_position_for(@player_id)
          return unless headquarters_position

          headquarters = object_at(
            @visible_state,
            headquarters_position
          )

          return unless headquarters
          return if headquarters["has_attacked"]

          @candidates << {
            kind: :headquarters,
            key: [:headquarters, headquarters_position],
            origin: headquarters_position,
            destinations: [headquarters_position]
          }
        end

        def headquarters_position_for(player_id)
          field_objects(@visible_state).find do |object, _position|
            object["type"] == "headquarters" &&
              object["player_id"].to_s == player_id.to_s
          end&.last
        end

        # ------------------------------------------------------------
        # Перебор последовательностей атак
        # ------------------------------------------------------------

        def explore(state:, used_keys:, technique_count:)
          return if technique_count > MAX_TECHNIQUES

          @candidates.each do |candidate|
            next if used_keys.include?(candidate[:key])

            if candidate[:kind] == :technique &&
                technique_count >= MAX_TECHNIQUES
              next
            end

            candidate[:destinations].each do |destination|
              next_state = simulate_attack(
                state: state,
                candidate: candidate,
                destination: destination
              )

              next unless next_state

              next_used_keys = used_keys + [candidate[:key]]

              next_technique_count =
                technique_count +
                (candidate[:kind] == :technique ? 1 : 0)

              total_gain =
                state_score(next_state) - @initial_score

              if used_keys.empty?
                @best_single_gain = [
                  @best_single_gain,
                  total_gain
                ].max
              end

              if next_technique_count >= 2
                @best_combined_gain = [
                  @best_combined_gain,
                  total_gain
                ].max
              end

              # Если цель уничтожена, продолжать эту
              # последовательность атак невозможно.
              next unless object_at(next_state, @target_position)

              # После уничтожения любого штаба партия завершена.
              next if terminal_state?(next_state)

              # Штаб и три техники — максимальная
              # последовательность для одной цели.
              next if next_used_keys.length >= MAX_TECHNIQUES + 1

              explore(
                state: next_state,
                used_keys: next_used_keys,
                technique_count: next_technique_count
              )
            end
          end
        end

        # ------------------------------------------------------------
        # Симуляция одного перемещения и выстрела
        # ------------------------------------------------------------

        def simulate_attack(state:, candidate:, destination:)
          simulated_state = state.deep_dup

          attacker = object_at(
            simulated_state,
            candidate[:origin]
          )

          return nil unless attacker
          return nil if attacker["has_attacked"]
          return nil unless attacker["player_id"].to_s == @player_id

          attacker_position = candidate[:origin]

          if destination != attacker_position
            return nil unless attacker["type"] == "technique"
            return nil unless attacker["movement_count"].to_i.positive?
            return nil if object_at(simulated_state, destination)

            return nil unless GameEngine::Rules::TechniqueMovement.valid?(
              attacker,
              attacker_position,
              destination
            )

            attacker["movement_count"] -= 1

            set_object(
              simulated_state,
              attacker_position,
              nil
            )

            set_object(
              simulated_state,
              destination,
              attacker
            )

            attacker_position = destination
          end

          target = object_at(
            simulated_state,
            @target_position
          )

          return nil unless target
          return nil if target["player_id"].to_s == @player_id

          return nil unless GameEngine::Rules::AttackTarget.valid?(
            state: simulated_state,
            attacker: attacker,
            target: target,
            attacker_position: attacker_position,
            target_position: @target_position
          )

          scenario = GameEngine::Rules::CombatType.call(
            attacker: attacker,
            target: target,
            attacker_position: attacker_position,
            target_position: @target_position
          )

          attacker["has_attacked"] = true

          GameEngine::Attacks::CombatExecutor.call(
            state: simulated_state,
            attacker_position: attacker_position,
            target_position: @target_position,
            scenario: scenario
          )

          simulated_state
        end

        # ------------------------------------------------------------
        # Оценка результата симуляции
        # ------------------------------------------------------------

        def state_score(state)
          terminal_score = terminal_score_for(state)

          return terminal_score unless terminal_score.nil?

          @material_scorer.call(state)
        end

        def terminal_state?(state)
          !terminal_score_for(state).nil?
        end

        def terminal_score_for(state)
          own_headquarters = headquarters_for(
            state,
            @player_id
          )

          enemy_headquarters = headquarters_for(
            state,
            @opponent_id
          )

          return -StrategicEvaluator::WIN_SCORE unless
            own_headquarters &&
            own_headquarters["hp"].to_i.positive?

          return StrategicEvaluator::WIN_SCORE unless
            enemy_headquarters &&
            enemy_headquarters["hp"].to_i.positive?

          nil
        end

        def headquarters_for(state, player_id)
          field_objects(state).find do |object, _position|
            object["type"] == "headquarters" &&
              object["player_id"].to_s == player_id.to_s
          end&.first
        end

        # ------------------------------------------------------------
        # Подготовка изолированного состояния
        # ------------------------------------------------------------

        def simulation_state(visible_state)
          state = visible_state.deep_dup

          # VisibleState не содержит реальные кладбища.
          # CombatExecutor использует их при уничтожении техники.
          state.fetch("players").each_value do |player|
            player["graveyard"] ||= []
          end

          state
        end

        # ------------------------------------------------------------
        # Работа с полем
        # ------------------------------------------------------------

        def object_at(state, position)
          state.dig("field", position[0], position[1])
        end

        def set_object(state, position, object)
          state["field"][position[0]][position[1]] = object
        end

        def field_objects(state)
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
      end
    end
  end
end
