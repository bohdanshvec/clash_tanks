require "test_helper"

class GameEngine::ActionTest < ActiveSupport::TestCase
  test "creates action with player_id and type" do
    action = GameEngine::Action.new(
      player_id: 42,
      type: "end_turn"
    )

    assert_equal 42, action.player_id
    assert_equal "end_turn", action.type
  end

  test "payload defaults to empty hash" do
    action = GameEngine::Action.new(
      player_id: 42,
      type: "end_turn"
    )

    assert_equal({}, action.payload)
  end

  test "stores payload" do
    payload = {
      card_id: 17,
      to: [1, 2]
    }

    action = GameEngine::Action.new(
      player_id: 42,
      type: "move",
      payload: payload
    )

    assert_equal payload, action.payload
  end

  test "action is immutable" do
    action = GameEngine::Action.new(
      player_id: 42,
      type: "end_turn"
    )

    assert_predicate action, :frozen?
    assert_predicate action.payload, :frozen?
  end
end
