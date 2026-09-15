require "test_helper"

class GameEngine::TurnTimerTest < ActiveSupport::TestCase
  PLAYER_ID = 42
  OPPONENT_ID = 57

	setup do
		@started_at = Time.current.change(usec: 0)

		@state = GameEngine::GameState.initial(
		  current_player_id: PLAYER_ID,
		  participants: [
		    { player_id: PLAYER_ID, nation_id: 10 },
		    { player_id: OPPONENT_ID, nation_id: 20 }
		  ]
		)

		@state["turn_started_at"] = @started_at.iso8601(6)
	end

  test "does not expire before remaining time is over" do
    current_time = @started_at + 599

    timer = GameEngine::TurnTimer.new(
      @state,
      current_time: current_time
    )

    refute timer.expired?
  end

  test "expires when remaining time is over" do
    current_time = @started_at + 600

    timer = GameEngine::TurnTimer.new(
      @state,
      current_time: current_time
    )

    assert timer.expired?
  end

  test "calculates remaining time after elapsed time" do
    current_time = @started_at + 30

    timer = GameEngine::TurnTimer.new(
      @state,
      current_time: current_time
    )

    assert_equal 570, timer.remaining_time_after_elapsed
  end

  test "does not return negative remaining time" do
    current_time = @started_at + 601

    timer = GameEngine::TurnTimer.new(
      @state,
      current_time: current_time
    )

    assert_equal 0, timer.remaining_time_after_elapsed
  end

  test "uses current player's remaining time" do
    @state["players"][PLAYER_ID.to_s]["remaining_time"] = 500
    current_time = @started_at + 500

    timer = GameEngine::TurnTimer.new(
      @state,
      current_time: current_time
    )

    assert timer.expired?
  end
end
