require "test_helper"

class GameEngine::Abilities::DrawCardsTest < ActiveSupport::TestCase
  test "draws the requested number of cards" do
    player_id = 1

    card1 = { "card_id" => 10 }
    card2 = { "card_id" => 20 }

    state = {
      "players" => {
        player_id.to_s => {
          "hand" => [],
          "deck" => [card1, card2],
          "graveyard" => [],
          "empty_deck_draw_attempts" => 0
        }
      },
      "field" => [
        [
          {
            "type" => "headquarters",
            "player_id" => player_id,
            "hp" => 20
          }
        ]
      ]
    }

    result = GameEngine::Abilities::DrawCards.new(
      state: state,
      ability: {
        "code" => "draw_cards",
        "count" => 2
      },
      player_id: player_id,
      targets: []
    ).call

    assert result.success?
    assert_equal(
      [card1, card2],
      result.state["players"][player_id.to_s]["hand"]
    )
    assert_empty result.state["players"][player_id.to_s]["deck"]
  end

  test "rejects invalid draw count" do
    state = {
      "players" => {
        "1" => {
          "hand" => [],
          "deck" => [],
          "graveyard" => [],
          "empty_deck_draw_attempts" => 0
        }
      },
      "field" => []
    }

    result = GameEngine::Abilities::DrawCards.new(
      state: state,
      ability: {
        "code" => "draw_cards",
        "count" => 0
      },
      player_id: 1,
      targets: []
    ).call

    refute result.success?
    assert_equal "Invalid draw count", result.error
  end
end
