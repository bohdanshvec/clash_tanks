# app/services/games/run_ai_turns.rb

module Games
  class RunAiTurns
    Result = Data.define(:success?, :error, :events, :actions_count)

    MAX_ACTIONS_PER_RUN = 20
    
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
			on_action: nil
		)
			new(
				game:,
				max_actions:,
				decision_source:,
				on_action:
			).call
		end

		def initialize(
			game:,
			max_actions:,
			decision_source: nil,
			on_action: nil
		)
			@game = game
			@max_actions = max_actions
			@decision_source = decision_source
			@on_action = on_action
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
        provider_options = { context: context }

        if @decision_source
          provider_options[:decision_source] = @decision_source
        end

				action = DecisionProviders::AI.new(**provider_options).call

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
