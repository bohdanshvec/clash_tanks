require "test_helper"

class GameEngine::TurnTimerForTurnTest < ActiveSupport::TestCase
  PLAYER_ID = 42
  OPPONENT_ID = 57

  setup do
    @started_at = Time.current.change(usec: 0)

    @state = GameEngine::GameState.initial(
      current_player_id: PLAYER_ID,
      participants: [
        headquarters_participant(player_id: PLAYER_ID, nation_id: 10),
        headquarters_participant(player_id: OPPONENT_ID, nation_id: 20)
      ]
    )

    @state["turn_started_at"] = @started_at.iso8601
  end

  test "does not expire before two minutes" do
    current_time = @started_at + 119

    timer = GameEngine::TurnTimerForTurn.new(
      @state,
      current_time: current_time
    )

    refute timer.expired?
  end

  test "expires after two minutes" do
    current_time = @started_at + 120

    timer = GameEngine::TurnTimerForTurn.new(
      @state,
      current_time: current_time
    )

    assert timer.expired?
  end

  test "calculates remaining turn time" do
    current_time = @started_at + 30

    timer = GameEngine::TurnTimerForTurn.new(
      @state,
      current_time: current_time
    )

    assert_equal 90, timer.remaining_time
  end

  test "does not return negative remaining time" do
    current_time = @started_at + 121

    timer = GameEngine::TurnTimerForTurn.new(
      @state,
      current_time: current_time
    )

    assert_equal 0, timer.remaining_time
  end
end
