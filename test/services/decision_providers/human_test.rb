require "test_helper"

class DecisionProvidersHumanTest < ActiveSupport::TestCase
  test "creates an action with the supplied player and type" do
    action = DecisionProviders::Human.new(
      player_id: "42",
      type: "end_turn"
    ).call

    assert_instance_of GameEngine::Action, action
    assert_equal "42", action.player_id
    assert_equal "end_turn", action.type
    assert_equal({}, action.payload)
  end

  test "passes the supplied payload to the action" do
    payload = {
      from: [1, 1],
      to: [1, 2]
    }

    action = DecisionProviders::Human.new(
      player_id: "42",
      type: "move",
      payload: payload
    ).call

    assert_instance_of GameEngine::Action, action
    assert_equal "move", action.type
    assert_equal payload, action.payload
  end
end
