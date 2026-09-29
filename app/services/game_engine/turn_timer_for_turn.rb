module GameEngine
  class TurnTimerForTurn
    def initialize(state, current_time: Time.current)
      @state = state
      @current_time = current_time
    end

    def expired?
      elapsed_seconds >= GameState::TURN_TIME
    end

    def remaining_time
      [GameState::TURN_TIME - elapsed_seconds.ceil, 0].max
    end

    private

    def elapsed_seconds
      started_at = Time.iso8601(@state.fetch("turn_started_at"))

      [@current_time - started_at, 0].max
    end
  end
end
