require "test_helper"

class GameEngine::GameStateTest < ActiveSupport::TestCase
  test "initial returns the default game state" do
    state = GameEngine::GameState.initial(
      current_player_id: 42,
      player_ids: [42, 57]
    )

    assert_equal 1, state["turn_number"]
    assert_equal 42, state["current_player_id"]

    assert_equal(
      {
        "42" => {
          "hand" => [],
          "resources" => 0,
          "remaining_time" => nil
        },
        "57" => {
          "hand" => [],
          "resources" => 0,
          "remaining_time" => nil
        }
      },
      state["players"]
    )

    assert_equal(
      [
        [nil, nil, nil, nil, nil],
        [nil, nil, nil, nil, nil],
        [nil, nil, nil, nil, nil]
      ],
      state["field"]
    )
  end
end
