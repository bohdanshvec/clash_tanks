
require "test_helper"

class DecisionProviders::ActionOptionsTest < ActiveSupport::TestCase
  test "removes duplicate actions created by copies of the same card" do
    visible_state = {
      "status" => "started",
      "current_player_id" => "42",
      "players" => {
        "42" => {
          "hand" => [
            { "card_id" => 99, "card_type" => "platoon" },
            { "card_id" => 99, "card_type" => "platoon" },
            { "card_id" => 100, "card_type" => "platoon" }
          ]
        }
      },
      "available_actions" => {
        "field" => {},
        "hand" => {
          "99" => {
            "resources_sufficient" => true,
            "slots" => [0, 1]
          },
          "100" => {
            "resources_sufficient" => true,
            "slots" => [0, 1]
          }
        }
      }
    }

    actions = DecisionProviders::ActionOptions.call(visible_state)

    play_actions = actions.select do |action|
      action["type"] == "play_card"
    end

    assert_equal(
      [99, 100],
      play_actions.map { |action| action.dig("payload", "card_id") }
    )

    assert_equal(
      1,
      actions.count { |action| action["type"] == "end_turn" }
    )
  end
end
