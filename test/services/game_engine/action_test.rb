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
  
	test "nested payload data is immutable" do
		action = GameEngine::Action.new(
		  player_id: 1,
		  type: "move",
		  payload: {
		    from: [1, 1],
		    metadata: {
		      target: [1, 2]
		    }
		  }
		)

		assert_raises(FrozenError) do
		  action.payload[:from][0] = 2
		end

		assert_raises(FrozenError) do
		  action.payload[:metadata][:target][0] = 2
		end
	end

	test "does not retain mutable references to original payload" do
		payload = {
		  from: [1, 1]
		}

		action = GameEngine::Action.new(
		  player_id: 1,
		  type: "move",
		  payload: payload
		)

		payload[:from][0] = 2

		assert_equal [1, 1], action.payload[:from]
	end
end
