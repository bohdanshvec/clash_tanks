require "test_helper"

class GameEngine::EngineTest < ActiveSupport::TestCase
  setup do
    @state = GameEngine::GameState.initial(
      current_player_id: 42,
      participants: [
        headquarters_participant(player_id: 42, nation_id: 10),
        headquarters_participant(player_id: 57, nation_id: 20)
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

  test "executes play_card for current player" do
    @state["players"]["42"]["resources"] = 5
    @state["players"]["42"]["hand"] = [
      {
        "card_id" => 15,
        "name" => "Т-34",
        "card_type" => "technique",
        "nation_id" => 10,
        "weight" => 1,
        "price" => 2,
        "technique" => {
          "technique_type" => "medium_tank",
          "attack_range" => 1,
          "movement_count" => 1,
          "movement_type" => "diagonal",
          "firepower" => 4,
          "hp" => 10,
          "fuel" => 2
        }
      }
    ]

    action = GameEngine::Action.new(
      player_id: 42,
      type: "play_card",
      payload: {
        card_id: 15,
        row: 2,
        column: 1
      }
    )

    result = GameEngine::Engine.new(@state).call(action)

    assert_predicate result, :success?
    assert_empty result.state["players"]["42"]["hand"]
    assert_equal 3, result.state["players"]["42"]["resources"]

    technique = result.state["field"][2][1]

    assert_equal "technique", technique["type"]
    assert_equal 15, technique["card_id"]
    assert_equal 42, technique["player_id"]
  end
  
  test "rejects action when current player's time has expired" do
    started_at = Time.iso8601(@state["turn_started_at"])
    current_time = started_at + 600

    action = GameEngine::Action.new(
      player_id: 42,
      type: "move",
      payload: {
        from: [1, 1],
        to: [0, 2]
      }
    )

    result = GameEngine::Engine.new(
      @state,
      current_time: current_time
    ).call(action)

    refute_predicate result, :success?
    assert_equal "Time expired", result.error
    assert_equal "technique", @state["field"][1][1]["type"]
  end

  test "allows action when current player's time has not expired" do
    started_at = Time.iso8601(@state["turn_started_at"])
    current_time = started_at + 30

    action = GameEngine::Action.new(
      player_id: 42,
      type: "move",
      payload: {
        from: [1, 1],
        to: [0, 2]
      }
    )

    result = GameEngine::Engine.new(
      @state,
      current_time: current_time
    ).call(action)

    assert_predicate result, :success?
    assert_nil result.state["field"][1][1]
    assert_equal "technique", result.state["field"][0][2]["type"]
  end
end
