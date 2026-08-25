require "test_helper"

class GameEngine::EngineTest < ActiveSupport::TestCase
  setup do
    @state = GameEngine::GameState.initial(
      current_player_id: 42,
      player_ids: [42, 57]
    )
  end

  test "executes end_turn for current player" do
    action = GameEngine::Action.new(
      player_id: 42,
      type: "end_turn"
    )

    result = GameEngine::Engine.new(@state).call(action)

    assert_predicate result, :success?
    assert_equal 2, result.state["turn_number"]
    assert_equal 57, result.state["current_player_id"]
  end

  test "rejects end_turn from another player" do
    action = GameEngine::Action.new(
      player_id: 57,
      type: "end_turn"
    )

    result = GameEngine::Engine.new(@state).call(action)

    refute_predicate result, :success?
    assert_equal "It is not player's turn", result.error
  end

  test "does not change original state" do
    action = GameEngine::Action.new(
      player_id: 42,
      type: "end_turn"
    )

    GameEngine::Engine.new(@state).call(action)

    assert_equal 1, @state["turn_number"]
    assert_equal 42, @state["current_player_id"]
  end

  test "rejects unknown action type" do
    action = GameEngine::Action.new(
      player_id: 42,
      type: "unknown_action"
    )

    result = GameEngine::Engine.new(@state).call(action)

    refute_predicate result, :success?
    assert_equal "Unknown action type", result.error
    assert_nil result.state
  end

  test "returns turn ended event" do
    action = GameEngine::Action.new(
      player_id: 42,
      type: "end_turn"
    )

    result = GameEngine::Engine.new(@state).call(action)

    assert_equal [{ type: "turn_ended" }], result.events
  end
end
