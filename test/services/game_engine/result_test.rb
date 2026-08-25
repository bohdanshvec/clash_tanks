require "test_helper"

class GameEngine::ResultTest < ActiveSupport::TestCase
  test "creates successful result" do
    state = {
      "turn_number" => 2,
      "current_player_id" => 57
    }

    result = GameEngine::Result.new(
      success: true,
      state: state
    )

    assert_predicate result, :success?
    assert_nil result.error
    assert_equal state, result.state
    assert_equal [], result.events
  end

  test "creates failed result with error" do
    result = GameEngine::Result.new(
      success: false,
      error: "It is not player's turn"
    )

    refute_predicate result, :success?
    assert_equal "It is not player's turn", result.error
    assert_nil result.state
    assert_equal [], result.events
  end

  test "stores events" do
    events = [
      { type: "turn_ended" }
    ]

    result = GameEngine::Result.new(
      success: true,
      events: events
    )

    assert_equal events, result.events
  end

  test "result is immutable" do
    result = GameEngine::Result.new(
      success: true,
      state: {},
      events: []
    )

    assert_predicate result, :frozen?
    assert_predicate result.events, :frozen?
  end
end
