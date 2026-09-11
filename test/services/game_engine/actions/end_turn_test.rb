require "test_helper"

class GameEngine::Actions::EndTurnTest < ActiveSupport::TestCase
  PLAYER_ID = 1
  OPPONENT_ID = 2

  def setup
    @state = GameEngine::GameState.initial(
      current_player_id: PLAYER_ID,
      participants: [
        { player_id: PLAYER_ID, nation_id: 10 },
        { player_id: OPPONENT_ID, nation_id: 20 }
      ]
    )
  end

  test "ends current player's turn" do
    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "end_turn"
    )

    result = GameEngine::Actions::EndTurn.new(@state, action).call

    assert result.success?
    assert_equal 2, result.state["turn_number"]
    assert_equal OPPONENT_ID, result.state["current_player_id"]
    assert_equal [{ type: "turn_ended" }], result.events
  end

  test "does not allow ending opponent's turn" do
    action = GameEngine::Action.new(
      player_id: OPPONENT_ID,
      type: "end_turn"
    )

    result = GameEngine::Actions::EndTurn.new(@state, action).call

    assert_not result.success?
    assert_equal "It is not player's turn", result.error
  end

  test "does not allow unknown player to end turn" do
    action = GameEngine::Action.new(
      player_id: 999,
      type: "end_turn"
    )

    result = GameEngine::Actions::EndTurn.new(@state, action).call

    assert_not result.success?
    assert_equal "Player does not exist", result.error
  end

  test "does not modify original state" do
    original_state = Marshal.load(Marshal.dump(@state))

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "end_turn"
    )

    result = GameEngine::Actions::EndTurn.new(@state, action).call

    assert result.success?
    assert_equal original_state, @state
  end

  test "turn alternates back to first player" do
    first_action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "end_turn"
    )

    first_result = GameEngine::Actions::EndTurn.new(
      @state,
      first_action
    ).call

    second_action = GameEngine::Action.new(
      player_id: OPPONENT_ID,
      type: "end_turn"
    )

    second_result = GameEngine::Actions::EndTurn.new(
      first_result.state,
      second_action
    ).call

    assert second_result.success?
    assert_equal 3, second_result.state["turn_number"]
    assert_equal PLAYER_ID, second_result.state["current_player_id"]
  end
end
