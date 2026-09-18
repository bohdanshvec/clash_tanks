require "test_helper"

class GameEngine::Cards::DrawTest < ActiveSupport::TestCase
  test "draws cards from deck to hand" do
    player_id = 1

    card1 = { "card_id" => 10, "name" => "Card 1" }
    card2 = { "card_id" => 20, "name" => "Card 2" }

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
          nil,
          nil,
          nil,
          nil,
          {
            "type" => "headquarters",
            "player_id" => player_id,
            "hp" => 20
          }
        ]
      ]
    }

    result = GameEngine::Cards::Draw.call(
      state: state,
      player_id: player_id,
      count: 2
    )

    assert result.success?
    assert_equal(
      [card1, card2],
      result.state["players"][player_id.to_s]["hand"]
    )
    assert_empty result.state["players"][player_id.to_s]["deck"]
    assert_equal(
      0,
      result.state["players"][player_id.to_s]["empty_deck_draw_attempts"]
    )
  end

  test "does not modify original state" do
    player_id = 1
    card = { "card_id" => 10 }

    state = {
      "players" => {
        player_id.to_s => {
          "hand" => [],
          "deck" => [card],
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

    original_state = state.deep_dup

    GameEngine::Cards::Draw.call(
      state: state,
      player_id: player_id,
      count: 1
    )

    assert_equal original_state, state
  end

  test "damages headquarters when deck is empty" do
    player_id = 1

    state = {
      "players" => {
        player_id.to_s => {
          "hand" => [],
          "deck" => [],
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

    result = GameEngine::Cards::Draw.call(
      state: state,
      player_id: player_id,
      count: 1
    )

    assert result.success?
    assert_equal 19, result.state["field"][0][0]["hp"]
    assert_equal(
      1,
      result.state["players"][player_id.to_s]["empty_deck_draw_attempts"]
    )
  end

  test "empty deck damage increases on every failed draw attempt" do
    player_id = 1

    state = {
      "players" => {
        player_id.to_s => {
          "hand" => [],
          "deck" => [],
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

    result = GameEngine::Cards::Draw.call(
      state: state,
      player_id: player_id,
      count: 2
    )

    assert result.success?
    assert_equal 17, result.state["field"][0][0]["hp"]
    assert_equal(
      2,
      result.state["players"][player_id.to_s]["empty_deck_draw_attempts"]
    )
  end

  test "draws available card and then damages headquarters on next attempt" do
    player_id = 1
    card = { "card_id" => 10 }

    state = {
      "players" => {
        player_id.to_s => {
          "hand" => [],
          "deck" => [card],
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

    result = GameEngine::Cards::Draw.call(
      state: state,
      player_id: player_id,
      count: 2
    )

    player_state = result.state["players"][player_id.to_s]

    assert result.success?
    assert_equal [card], player_state["hand"]
    assert_empty player_state["deck"]
    assert_equal 19, result.state["field"][0][0]["hp"]
    assert_equal 1, player_state["empty_deck_draw_attempts"]
  end

  test "does not add drawn cards to graveyard" do
    player_id = 1
    card = { "card_id" => 10 }

    state = {
      "players" => {
        player_id.to_s => {
          "hand" => [],
          "deck" => [card],
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

    result = GameEngine::Cards::Draw.call(
      state: state,
      player_id: player_id,
      count: 1
    )

    assert_empty result.state["players"][player_id.to_s]["graveyard"]
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

    result = GameEngine::Cards::Draw.call(
      state: state,
      player_id: 1,
      count: 0
    )

    refute result.success?
    assert_equal "Invalid draw count", result.error
  end
  
	test "finishes game when empty deck damage destroys headquarters" do
		player_id = 1
		opponent_id = 2

		state = {
		  "status" => "started",
		  "players" => {
		    player_id.to_s => {
		      "hand" => [],
		      "deck" => [],
		      "graveyard" => [],
		      "empty_deck_draw_attempts" => 0
		    },
		    opponent_id.to_s => {
		      "hand" => [],
		      "deck" => [],
		      "graveyard" => [],
		      "empty_deck_draw_attempts" => 0
		    }
		  },
		  "field" => [
		    [
		      {
		        "type" => "headquarters",
		        "player_id" => player_id,
		        "hp" => 1
		      },
		      nil,
		      nil,
		      nil,
		      {
		        "type" => "headquarters",
		        "player_id" => opponent_id,
		        "hp" => 20
		      }
		    ]
		  ]
		}

		result = GameEngine::Cards::Draw.call(
		  state: state,
		  player_id: player_id,
		  count: 1
		)

		assert result.success?, result.error

		assert_equal 0, result.state["field"][0][0]["hp"]
		assert_equal "finished", result.state["status"]

		assert_equal(
		  {
				"winner_id" => opponent_id.to_s,
				"loser_id" => player_id.to_s,
				"reason" => "empty_deck_damage"
		  },
		  result.state["result"]
		)

		assert_equal(
		  {
		    type: "empty_deck_draw_attempt",
		    player_id: player_id.to_s,
		    damage: 1
		  },
		  result.events[0]
		)

		assert_equal(
		  {
		    type: "game_finished",
				winner_id: opponent_id.to_s,
				loser_id: player_id.to_s,
		    reason: "empty_deck_damage"
		  },
		  result.events[1]
		)
	end

	test "empty deck game finish does not modify original state" do
		player_id = 1
		opponent_id = 2

		state = {
		  "status" => "started",
		  "players" => {
		    player_id.to_s => {
		      "hand" => [],
		      "deck" => [],
		      "graveyard" => [],
		      "empty_deck_draw_attempts" => 0
		    },
		    opponent_id.to_s => {
		      "hand" => [],
		      "deck" => [],
		      "graveyard" => [],
		      "empty_deck_draw_attempts" => 0
		    }
		  },
		  "field" => [
		    [
		      {
		        "type" => "headquarters",
		        "player_id" => player_id,
		        "hp" => 1
		      },
		      nil,
		      nil,
		      nil,
		      {
		        "type" => "headquarters",
		        "player_id" => opponent_id,
		        "hp" => 20
		      }
		    ]
		  ]
		}

		original_state = state.deep_dup

		result = GameEngine::Cards::Draw.call(
		  state: state,
		  player_id: player_id,
		  count: 1
		)

		assert result.success?, result.error
		assert_equal original_state, state
	end

	test "empty deck damage does not finish game while headquarters survives" do
		player_id = 1
		opponent_id = 2

		state = {
		  "status" => "started",
		  "players" => {
		    player_id.to_s => {
		      "hand" => [],
		      "deck" => [],
		      "graveyard" => [],
		      "empty_deck_draw_attempts" => 0
		    },
		    opponent_id.to_s => {
		      "hand" => [],
		      "deck" => [],
		      "graveyard" => [],
		      "empty_deck_draw_attempts" => 0
		    }
		  },
		  "field" => [
		    [
		      {
		        "type" => "headquarters",
		        "player_id" => player_id,
		        "hp" => 10
		      },
		      nil,
		      nil,
		      nil,
		      {
		        "type" => "headquarters",
		        "player_id" => opponent_id,
		        "hp" => 20
		      }
		    ]
		  ]
		}

		result = GameEngine::Cards::Draw.call(
		  state: state,
		  player_id: player_id,
		  count: 1
		)

		assert result.success?, result.error

		assert_equal 9, result.state["field"][0][0]["hp"]
		assert_equal "started", result.state["status"]
		assert_nil result.state["result"]
	end
end
