require "test_helper"

class GameEngine::FinishGameTest < ActiveSupport::TestCase
  PLAYER_ID = 42
  OPPONENT_ID = 57

  setup do
    @state = GameEngine::GameState.initial(
      current_player_id: PLAYER_ID,
      participants: [
        headquarters_participant(player_id: PLAYER_ID, nation_id: 10),
        headquarters_participant(player_id: OPPONENT_ID, nation_id: 20)
      ]
    )
  end

  test "finishes game and stores result" do
    result = GameEngine::FinishGame.call(
      state: @state,
      winner_id: PLAYER_ID,
      loser_id: OPPONENT_ID,
      reason: "headquarters_destroyed"
    )

    assert_predicate result, :success?
    assert_equal "finished", result.state["status"]
    assert_equal(
      {
        "winner_id" => PLAYER_ID,
        "loser_id" => OPPONENT_ID,
        "reason" => "headquarters_destroyed"
      },
      result.state["result"]
    )
  end

  test "returns game finished event" do
    result = GameEngine::FinishGame.call(
      state: @state,
      winner_id: PLAYER_ID,
      loser_id: OPPONENT_ID,
      reason: "headquarters_destroyed"
    )

    assert_equal(
      [
        {
          type: "game_finished",
          winner_id: PLAYER_ID,
          loser_id: OPPONENT_ID,
          reason: "headquarters_destroyed"
        }
      ],
      result.events
    )
  end

  test "does not modify original state" do
    result = GameEngine::FinishGame.call(
      state: @state,
      winner_id: PLAYER_ID,
      loser_id: OPPONENT_ID,
      reason: "headquarters_destroyed"
    )

    assert_equal "started", @state["status"]
    assert_nil @state["result"]
    refute_same @state, result.state
  end

  test "rejects already finished game" do
    @state["status"] = "finished"

    result = GameEngine::FinishGame.call(
      state: @state,
      winner_id: PLAYER_ID,
      loser_id: OPPONENT_ID,
      reason: "headquarters_destroyed"
    )

    refute_predicate result, :success?
    assert_equal "Game is already finished", result.error
    assert_nil result.state
  end

  test "rejects unknown winner" do
    result = GameEngine::FinishGame.call(
      state: @state,
      winner_id: 999,
      loser_id: OPPONENT_ID,
      reason: "headquarters_destroyed"
    )

    refute_predicate result, :success?
    assert_equal "Winner does not exist", result.error
  end

  test "rejects unknown loser" do
    result = GameEngine::FinishGame.call(
      state: @state,
      winner_id: PLAYER_ID,
      loser_id: 999,
      reason: "headquarters_destroyed"
    )

    refute_predicate result, :success?
    assert_equal "Loser does not exist", result.error
  end

  test "rejects same winner and loser" do
    result = GameEngine::FinishGame.call(
      state: @state,
      winner_id: PLAYER_ID,
      loser_id: PLAYER_ID,
      reason: "headquarters_destroyed"
    )

    refute_predicate result, :success?
    assert_equal "Winner and loser must be different", result.error
  end

  test "rejects invalid reason" do
    result = GameEngine::FinishGame.call(
      state: @state,
      winner_id: PLAYER_ID,
      loser_id: OPPONENT_ID,
      reason: "unknown"
    )

    refute_predicate result, :success?
    assert_equal "Invalid finish reason", result.error
  end
end
