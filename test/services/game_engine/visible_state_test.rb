require "test_helper"

class GameEngine::VisibleStateTest < ActiveSupport::TestCase
  setup do
    @state = {
      "status" => "started",
      "turn_number" => 3,
      "current_player_id" => 1,
      "players" => {
        "1" => {
          "nation_id" => 10,
          "hand" => [
            { "card_id" => 101, "name" => "T-34" },
            { "card_id" => 102, "name" => "ИС-2" }
          ],
          "deck" => [
            { "card_id" => 103, "name" => "Т-70" },
            { "card_id" => 104, "name" => "СУ-85" },
            { "card_id" => 105, "name" => "Катюша" }
          ],
          "graveyard" => [
            { "card_id" => 106, "name" => "Уничтоженная карта" }
          ],
          "platoons" => [nil, nil, nil, nil],
          "resources" => 5,
          "remaining_time" => 500,
          "empty_deck_draw_attempts" => 0
        },
        "2" => {
          "nation_id" => 20,
          "hand" => [
            { "card_id" => 201, "name" => "Panther" },
            { "card_id" => 202, "name" => "Tiger" }
          ],
          "deck" => [
            { "card_id" => 203, "name" => "Pz IV" }
          ],
          "graveyard" => [
            { "card_id" => 204, "name" => "Discarded Order" }
          ],
          "platoons" => [nil, nil, nil, nil],
          "resources" => 7,
          "remaining_time" => 400,
          "empty_deck_draw_attempts" => 0
        }
      },
      "field" => [
        [nil, nil, nil, nil, nil],
        [nil, nil, nil, nil, nil],
        [nil, nil, nil, nil, nil]
      ]
    }
  end

  test "shows own hand and hides opponent hand" do
    visible_state = GameEngine::VisibleState.call(
      state: @state,
      player_id: 1
    )

    own_player = visible_state["players"]["1"]
    opponent = visible_state["players"]["2"]

    assert_equal 2, own_player["hand"].length
    assert_equal "T-34", own_player["hand"].first["name"]

    assert_equal 2, opponent["hand_count"]
    refute opponent.key?("hand")
  end

  test "shows deck counts without exposing deck contents" do
    visible_state = GameEngine::VisibleState.call(
      state: @state,
      player_id: 1
    )

    own_player = visible_state["players"]["1"]
    opponent = visible_state["players"]["2"]

    assert_equal 3, own_player["deck_count"]
    assert_equal 1, opponent["deck_count"]

    refute own_player.key?("deck")
    refute opponent.key?("deck")
  end

  test "does not expose graveyards" do
    visible_state = GameEngine::VisibleState.call(
      state: @state,
      player_id: 1
    )

    visible_state["players"].each_value do |player|
      refute player.key?("graveyard")
    end
  end

  test "hides opponent resources but shows opponent remaining time" do
    visible_state = GameEngine::VisibleState.call(
      state: @state,
      player_id: 1
    )

    own_player = visible_state["players"]["1"]
    opponent = visible_state["players"]["2"]

    assert_equal 5, own_player["resources"]
    assert_equal 500, own_player["remaining_time"]

    refute opponent.key?("resources")
    assert_equal 400, opponent["remaining_time"]
  end

  test "keeps public game state visible" do
    visible_state = GameEngine::VisibleState.call(
      state: @state,
      player_id: 1
    )

    assert_equal "started", visible_state["status"]
    assert_equal 3, visible_state["turn_number"]
    assert_equal 1, visible_state["current_player_id"]
    assert_equal @state["field"], visible_state["field"]
  end

  test "does not mutate original state" do
    original_state = @state.deep_dup

    visible_state = GameEngine::VisibleState.call(
      state: @state,
      player_id: 1
    )

    visible_state["players"]["1"]["hand"].first["name"] = "Changed"
    visible_state["field"][0][0] = { "changed" => true }

    assert_equal original_state, @state
  end
end
