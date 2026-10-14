class GameActionRunner
  Result = Data.define(:success?, :error, :state, :events)

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

    @game.with_lock do
      # После получения блокировки запись игры перечитывается из БД.
      if @game.waiting? && @game.state.nil?
        waiting_game = true
        next
      end

      engine_result = GameEngine::Engine.new(@game.state).call(@action)

      # Отклонённое действие не изменяет сохранённое состояние.
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

    Result.new(
      success?: engine_result.success?,
      error: engine_result.error,
      state: engine_result.success? ? engine_result.state : nil,
      events: engine_result.success? ? engine_result.events : []
    )
  end
end
