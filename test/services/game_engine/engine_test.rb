require "test_helper"

class GameEngine::EngineTest < ActiveSupport::TestCase
  setup do
    @state = GameEngine::GameState.initial(
      current_player_id: 42,
      participants: [
        { player_id: 42, nation_id: 10 },
        { player_id: 57, nation_id: 20 }
      ]
    )

    @state["field"][1][1] = {
      "type" => "technique",
      "card_id" => 15,
      "player_id" => 42,
      "technique_type" => "medium_tank",
      "hp" => 10,
      "firepower" => 4,
      "fuel" => 2,
      "attack_range" => 1,
      "movement_count" => 1,
      "movement_type" => "diagonal",
      "has_attacked" => false,
      "has_counterattacked" => false
    }
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

  test "executes move for current player" do
    action = GameEngine::Action.new(
      player_id: 42,
      type: "move",
      payload: {
        from: [1, 1],
        to: [0, 2]
      }
    )

    result = GameEngine::Engine.new(@state).call(action)

    assert_predicate result, :success?
    assert_nil result.state["field"][1][1]
    assert_equal "technique", result.state["field"][0][2]["type"]
    assert_equal 0, result.state["field"][0][2]["movement_count"]
  end
end
