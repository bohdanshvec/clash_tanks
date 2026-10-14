# app/services/game_action_runner.rb

class GameActionRunner
  Result = Data.define(:success?, :error, :state, :events)

  STALE_STATE_ERROR =
    "Game state changed while AI was deciding. A new decision is required."

  def self.call(game:, action:)
    new(game: game, action: action).call
  end

  def initialize(game:, action:)
    @game = game
    @action = action
  end

  def call
    engine_result = nil
    waiting_game = false
    stale_state = false

    @game.with_lock do
      # После получения блокировки запись игры перечитывается из БД.
      if @game.waiting? && @game.state.nil?
        waiting_game = true
        next
      end

      # Проверяем актуальность состояния, на котором основывалось
      # решение ИИ. Проверка выполняется под блокировкой.
      if @action.expected_state_digest.present?
        current_digest = GameEngine::StateDigest.call(@game.state)

        unless current_digest == @action.expected_state_digest
          stale_state = true
          next
        end
      end

      engine_result = GameEngine::Engine.new(@game.state).call(@action)

      # Отклонённое движком действие не изменяет сохранённое состояние.
      next unless engine_result.success?

      attributes = { state: engine_result.state }

      # Синхронизируем статус игры с состоянием, возвращённым движком.
      if engine_result.state["status"].present? &&
         engine_result.state["status"] != @game.status
        attributes[:status] = engine_result.state["status"]
      end

      @game.update!(attributes)
    end

    if waiting_game
      return Result.new(
        success?: false,
        error: "Game has not started",
        state: nil,
        events: []
      )
    end

    if stale_state
      return Result.new(
        success?: false,
        error: STALE_STATE_ERROR,
        state: nil,
        events: []
      )
    end

    Result.new(
      success?: engine_result.success?,
      error: engine_result.error,
      state: engine_result.success? ? engine_result.state : nil,
      events: engine_result.success? ? engine_result.events : []
    )
  end
end
