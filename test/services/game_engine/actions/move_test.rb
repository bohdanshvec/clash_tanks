require "test_helper"

class GameEngine::Actions::MoveTest < ActiveSupport::TestCase
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

    @state["field"][1][1] = {
      "type" => "technique",
      "card_id" => 15,
      "player_id" => PLAYER_ID,
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

  test "moves technique to an adjacent cell" do
    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "move",
      payload: {
        from: [1, 1],
        to: [0, 2]
      }
    )

    result = GameEngine::Actions::Move.new(@state, action).call

    assert result.success?
    assert_nil result.state["field"][1][1]
    assert_equal "technique", result.state["field"][0][2]["type"]
    assert_equal 0, result.state["field"][0][2]["movement_count"]
  end

  test "does not modify original state" do
    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "move",
      payload: {
        from: [1, 1],
        to: [0, 2]
      }
    )

    result = GameEngine::Actions::Move.new(@state, action).call

    assert result.success?
    assert_equal "technique", @state["field"][1][1]["type"]
    assert_nil @state["field"][0][2]
  end

  test "does not allow moving technique that does not belong to player" do
    @state["field"][1][1]["player_id"] = OPPONENT_ID

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "move",
      payload: {
        from: [1, 1],
        to: [0, 2]
      }
    )

    result = GameEngine::Actions::Move.new(@state, action).call

    assert_not result.success?
    assert_equal "Technique does not belong to player", result.error
  end

  test "does not allow moving when it is not player's turn" do
    @state["current_player_id"] = OPPONENT_ID

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "move",
      payload: {
        from: [1, 1],
        to: [0, 2]
      }
    )

    result = GameEngine::Actions::Move.new(@state, action).call

    assert_not result.success?
    assert_equal "It is not player's turn", result.error
  end

  test "does not allow moving when movement count is zero" do
    @state["field"][1][1]["movement_count"] = 0

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "move",
      payload: {
        from: [1, 1],
        to: [0, 2]
      }
    )

    result = GameEngine::Actions::Move.new(@state, action).call

    assert_not result.success?
    assert_equal "No movement remaining", result.error
  end

  test "does not allow moving to occupied cell" do
    @state["field"][0][2] = {
      "type" => "technique",
      "card_id" => 20,
      "player_id" => OPPONENT_ID
    }

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "move",
      payload: {
        from: [1, 1],
        to: [0, 2]
      }
    )

    result = GameEngine::Actions::Move.new(@state, action).call

    assert_not result.success?
    assert_equal "Destination cell is occupied", result.error
  end

  test "does not allow orthogonal technique to move diagonally" do
    @state["field"][1][1]["movement_type"] = "orthogonal"

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "move",
      payload: {
        from: [1, 1],
        to: [0, 2]
      }
    )

    result = GameEngine::Actions::Move.new(@state, action).call

    assert_not result.success?
    assert_equal "Invalid movement", result.error
  end

  test "allows orthogonal technique to move horizontally" do
    @state["field"][1][1]["movement_type"] = "orthogonal"

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "move",
      payload: {
        from: [1, 1],
        to: [1, 2]
      }
    )

    result = GameEngine::Actions::Move.new(@state, action).call

    assert result.success?
    assert_nil result.state["field"][1][1]
    assert_equal "technique", result.state["field"][1][2]["type"]
    assert_equal 0, result.state["field"][1][2]["movement_count"]
  end

  test "does not allow moving more than one cell" do
    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "move",
      payload: {
        from: [1, 1],
        to: [0, 3]
      }
    )

    result = GameEngine::Actions::Move.new(@state, action).call

    assert_not result.success?
    assert_equal "Invalid movement", result.error
  end

  test "does not allow moving onto headquarters" do
    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "move",
      payload: {
        from: [1, 1],
        to: [2, 0]
      }
    )

    result = GameEngine::Actions::Move.new(@state, action).call

    assert_not result.success?
    assert_equal "Destination cell is occupied", result.error
  end
end
