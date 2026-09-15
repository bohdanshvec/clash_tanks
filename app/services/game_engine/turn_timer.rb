module GameEngine
  class TurnTimer
    def initialize(state, current_time: Time.current)
      @state = state
      @current_time = current_time
    end

    def expired?
      elapsed_seconds >= remaining_time
    end

		def remaining_time_after_elapsed
			[remaining_time - elapsed_seconds.ceil, 0].max
		end

    private

    def remaining_time
      player["remaining_time"].to_i
    end

    def elapsed_seconds
      started_at = Time.iso8601(@state.fetch("turn_started_at"))
      [@current_time - started_at, 0].max
    end

    def player
      @state.fetch("players").fetch(@state.fetch("current_player_id").to_s)
    end
  end
end
