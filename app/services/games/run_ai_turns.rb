# app/services/games/run_ai_turns.rb

module Games
  class RunAiTurns
    Result = Data.define(:success?, :error, :events, :actions_count)

    MAX_ACTIONS_PER_RUN = 20
    ACTION_DELAY_SECONDS = 2.5
    
    # Максимальное количество повторных решений,
		# если состояние игры изменилось во время работы ИИ.
		MAX_STALE_STATE_RETRIES = 3

    # Отдельное пространство ключей PostgreSQL advisory lock.
    # Используется двухцелочисленный вариант блокировки.
    AI_TURN_LOCK_NAMESPACE = 1_129_603_401

    def self.call(
      game:,
      max_actions: MAX_ACTIONS_PER_RUN,
      decision_source: nil,
      on_action: nil,
      sleeper: nil
    )
      new(
        game:,
        max_actions:,
        decision_source:,
        on_action:,
        sleeper:
      ).call
    end

    def initialize(
      game:,
      max_actions:,
      decision_source: nil,
      on_action: nil,
      sleeper: nil
    )
      @game = game
      @max_actions = max_actions
      @decision_source = decision_source
      @on_action = on_action
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }
      @opponent_plan = nil
      @opponent_plan_expected_visible_state = nil
      @opponent_plan_step_index = nil
      @opponent_plan_player_id = nil
    end

    def call
      Game.connection_pool.with_connection do |connection|
        lock_id = @game.id.to_i

        acquired = connection.select_value(
          "SELECT pg_try_advisory_lock(" \
          "#{AI_TURN_LOCK_NAMESPACE}, #{lock_id})"
        )

        # Другой запрос уже выполняет цикл ИИ для этой игры.
        # Не запускаем второй цикл параллельно.
        unless acquired
          return success_result([], 0)
        end

        begin
          run_ai_loop
        ensure
          # Освобождаем блокировку даже при ошибке провайдера.
          connection.select_value(
            "SELECT pg_advisory_unlock(" \
            "#{AI_TURN_LOCK_NAMESPACE}, #{lock_id})"
          )
        end
      end
    	rescue StandardError => e
      Rails.logger.error(
        "[Games::RunAiTurns] Game ##{@game&.id}: " \
        "error_class=#{e.class}"
      )

      failure_result(
        "Не удалось выполнить ход ИИ. Подробности записаны в журнал приложения.",
        [],
        0
      )
    end

    private

    def select_ai_action(context:, current_player_id:)
      # Внедрённый источник решений используется для изолированных тестов.
      # В обычной игре всегда используется собственный Opponent Engine.
      if @decision_source
        return DecisionProviders::AI.new(
          context: context,
          decision_source: @decision_source
        ).call
      end

      if reusable_opponent_plan_step?(
        context: context,
        current_player_id: current_player_id
      )
        execution = DecisionProviders::OpponentEngine::ActionExecutor.execute(
          plan: @opponent_plan,
          context: context,
          step_index: @opponent_plan_step_index
        )

        store_plan_execution(execution)

        return execution.action
      end

      clear_opponent_plan

      decision = DecisionProviders::AI.new(
        context: context
      ).call_with_plan

      store_plan_decision(
        decision,
        current_player_id: current_player_id
      )

      decision.action
    end

    def reusable_opponent_plan_step?(context:, current_player_id:)
      return false unless @opponent_plan
      return false unless @opponent_plan_player_id == current_player_id
      return false unless @opponent_plan_expected_visible_state
      return false unless @opponent_plan_step_index

      return false unless @opponent_plan_step_index < @opponent_plan.actions.length

      return false unless visible_states_match?(
        @opponent_plan_expected_visible_state,
        context.visible_state
      )

      planned_action = @opponent_plan.actions.fetch(
        @opponent_plan_step_index
      )

      legal_actions = DecisionProviders::ActionOptions.call(
        context.visible_state
      )

      legal_actions.any? do |legal_action|
        normalize_action_for_comparison(legal_action) ==
          normalize_action_for_comparison(planned_action)
      end
    end

    def store_plan_decision(decision, current_player_id:)
      return unless decision.plan

      @opponent_plan = decision.plan
      @opponent_plan_expected_visible_state =
        decision.expected_visible_state
      @opponent_plan_step_index = decision.next_step_index
      @opponent_plan_player_id = current_player_id
    end

    def store_plan_execution(execution)
      @opponent_plan_expected_visible_state =
        execution.expected_visible_state
      @opponent_plan_step_index = execution.next_step_index
    end

    def clear_opponent_plan
      @opponent_plan = nil
      @opponent_plan_expected_visible_state = nil
      @opponent_plan_step_index = nil
      @opponent_plan_player_id = nil
    end

    # Сравниваем игровое состояние, исключая только поля,
    # которые закономерно меняются с течением реального времени.
    def visible_states_match?(expected, actual)
      normalize_visible_state(expected) ==
        normalize_visible_state(actual)
    end

    def normalize_visible_state(visible_state)
      normalized = visible_state.deep_dup

      normalized.delete("server_time")
      normalized.delete("turn_started_at")

      normalized.fetch("players", {}).each_value do |player|
        player.delete("remaining_time")
      end

      normalized
    end

    def normalize_action_for_comparison(action)
      {
        "type" => action["type"] || action[:type],
        "payload" => normalize_hash_for_comparison(
          action["payload"] || action[:payload] || {}
        )
      }
    end

    def normalize_hash_for_comparison(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, item), result|
          result[key.to_s] = normalize_hash_for_comparison(item)
        end
      when Array
        value.map { |item| normalize_hash_for_comparison(item) }
      else
        value
      end
    end

		def run_ai_loop
			events = []
			actions_count = 0
			stale_state_retries = 0

      loop do
        @game.reload

        # Игра больше не принимает действия.
        unless @game.started?
          return success_result(events, actions_count)
        end

        state = @game.state
        current_player_id = state["current_player_id"].to_s

        # Нет определённого игрока, чей сейчас ход.
        if current_player_id.empty?
          return failure_result(
            "Не удалось определить игрока, чей сейчас ход.",
            events,
            actions_count
          )
        end

        current_player = Player.find_by(id: current_player_id)

        # Игрок не найден — прекращаем автоматический цикл.
        unless current_player
          return failure_result(
            "Не удалось найти игрока, чей сейчас ход.",
            events,
            actions_count
          )
        end

        # Если сейчас ход человека, автоматический цикл завершён.
        unless current_player.ai?
          return success_result(events, actions_count)
        end

        # Защита от бесконечного цикла.
        if actions_count >= @max_actions
          return failure_result(
            "ИИ достиг ограничения действий за один запуск.",
            events,
            actions_count
          )
        end

        # Контекст содержит только доступную ИИ информацию.
        context = DecisionProviders::Context.new(
          state: state,
          player_id: current_player_id
        )
        
				# Диагностика доступных AI-действий.
				# Используется только VisibleState, без скрытых данных противника.
				visible_state = context.visible_state

				legal_actions = DecisionProviders::ActionOptions.call(
					visible_state
				)

				ai_player = visible_state.fetch(
					"players",
					{}
				).fetch(current_player_id, {})

				ai_hand = ai_player.fetch("hand", [])

				available_hand = visible_state.fetch(
					"available_actions",
					{}
				).fetch("hand", {})

				Rails.logger.info(
					"[AI Diagnostics] Game ##{@game.id}: " \
					"turn=#{state['turn_number']}, " \
					"resources=#{ai_player['resources']}, " \
					"hand_size=#{ai_hand.length}, " \
					"legal_actions_count=#{legal_actions.length}, " \
					"legal_action_types=#{legal_actions.map { |action|
						action['type']
					}.tally.inspect}"
				)

        # ИИ выбирает действие, но не применяет его самостоятельно.
        action = select_ai_action(
          context: context,
          current_player_id: current_player_id
        )

				Rails.logger.info(
					"[Games::RunAiTurns] Game ##{@game.id}: " \
					"AI proposed action type=#{action.type.inspect}"
				)

				# Единственный путь применения действия — через общий исполнитель.
				result = GameActionRunner.call(
					game: @game,
					action: action
				)

				unless result.success?
					Rails.logger.error(
						"[Games::RunAiTurns] Game ##{@game.id}: " \
						"AI action rejected: type=#{action.type.inspect}, " \
						"error=#{result.error.inspect}"
					)
				end

				unless result.success?
					if result.error == GameActionRunner::STALE_STATE_ERROR
						if stale_state_retries >= MAX_STALE_STATE_RETRIES
							return failure_result(
								"Не удалось получить актуальное решение ИИ после " \
								"#{MAX_STALE_STATE_RETRIES} повторов.",
								events,
								actions_count
							)
						end

						stale_state_retries += 1

            clear_opponent_plan

						Rails.logger.info(
							"[Games::RunAiTurns] Game ##{@game.id}: " \
							"AI decision became stale. " \
							"Retry #{stale_state_retries}/#{MAX_STALE_STATE_RETRIES}."
						)

						# Начинаем следующую итерацию.
						# В начале цикла игра будет перечитана из БД,
						# а новый Context будет создан на актуальном состоянии.
						next
					end

					return failure_result(
						result.error,
						events,
						actions_count
					)
				end

				action_events = Array(result.events)

				events.concat(action_events)
				actions_count += 1

				# Успешное действие уже сохранено GameActionRunner.
				# Уведомляем вызывающий код, чтобы он мог обновить интерфейс.
				# Ошибка отправки Turbo-обновления не должна отменять
				# успешно применённое действие или останавливать ход ИИ.
				if @on_action
					begin
						@on_action.call(action_events)
					rescue StandardError => e
						Rails.logger.error(
							"[Games::RunAiTurns] Game ##{@game.id}: " \
							"Action broadcast callback failed: " \
							"error_class=#{e.class}"
						)
					end
				end

        # Даём браузеру время воспроизвести визуальные эффекты
        # перед следующим действием ИИ.
        #
        # Не задерживаем выполнение, если:
        # - партия завершена;
        # - ход уже перешёл другому игроку;
        # - достигнут лимит действий.
        next_action_belongs_to_ai =
          result.state &&
          result.state["status"] == "started" &&
          result.state["current_player_id"].to_s == current_player_id

        if next_action_belongs_to_ai && actions_count < @max_actions
          @sleeper.call(ACTION_DELAY_SECONDS)
        end

				# Успешное действие означает, что цикл продолжился нормально.
				stale_state_retries = 0
      end
    rescue StandardError => e
      Rails.logger.error(
        "[Games::RunAiTurns] Game ##{@game&.id}: " \
        "#{e.class}: #{e.message}"
      )

      failure_result(
        "Не удалось выполнить ход ИИ. Подробности записаны в журнал приложения.",
        events || [],
        actions_count || 0
      )
    end

    def success_result(events, actions_count)
      Result.new(
        success?: true,
        error: nil,
        events: events,
        actions_count: actions_count
      )
    end

    def failure_result(error, events, actions_count)
      Result.new(
        success?: false,
        error: error,
        events: events,
        actions_count: actions_count
      )
    end
  end
end
