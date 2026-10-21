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
          "deck" => [ card1, card2 ],
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
      [ card1, card2 ],
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
          "deck" => [ card ],
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
          "deck" => [ card ],
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
    assert_equal [ card ], player_state["hand"]
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
          "deck" => [ card ],
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
          "empty_deck_draw_attempts" => 0,
          "platoons" => [ nil, nil, nil, nil ]
        },
        opponent_id.to_s => {
          "hand" => [],
          "deck" => [],
          "graveyard" => [],
          "empty_deck_draw_attempts" => 0,
          "platoons" => [ nil, nil, nil, nil ]
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

    # Штаб уничтожен.
    assert_equal 0, result.state["field"][0][0]["hp"]

    # Партия завершена.
    assert_equal "finished", result.state["status"]

    # Победителем становится противник.
    assert_equal(
      {
        "winner_id" => opponent_id.to_s,
        "loser_id" => player_id.to_s,
        "reason" => "empty_deck_damage"
      },
      result.state["result"]
    )

    # Первая попытка взять карту из пустой колоды.
    assert_equal 1, result.state["players"][player_id.to_s]["empty_deck_draw_attempts"]

    # Проверяем количество событий.
    assert_equal 3, result.events.size

    # Событие попытки взять карту.
    assert_equal(
      {
        type: "empty_deck_draw_attempt",
        player_id: player_id.to_s,
        damage: 1
      },
      result.events[0]
    )

    # Событие нанесения урона штабу.
    # Защитных взводов нет, поэтому весь урон получает штаб.
    assert_equal(
      {
        type: "damage_applied",
        source: {
          type: "empty_deck_draw"
        },
        target: {
          type: "headquarters",
          player_id: player_id,
          card_id: nil,
          name: nil,
          position: [ 0, 0 ]
        },
        damage: 1,
        hp_before: 1,
        hp_after: 0,
        incoming_damage: 1,
        armor_absorbed: 0,
        headquarters_damage: 1
      },
      result.events[1]
    )

    # Событие завершения партии.
    assert_equal(
      {
        type: "game_finished",
        winner_id: opponent_id.to_s,
        loser_id: player_id.to_s,
        reason: "empty_deck_damage"
      },
      result.events[2]
    )
  end

  test "empty deck damage is absorbed by defensive platoon" do
    player_id = 1
    opponent_id = 2

    state = {
      "status" => "started",
      "players" => {
        player_id.to_s => {
          "hand" => [],
          "deck" => [],
          "graveyard" => [],
          "empty_deck_draw_attempts" => 0,
          "platoons" => [
            {
              "type" => "platoon",
              "player_id" => player_id,
              "card_id" => 100,
              "name" => "Defensive Platoon",
              "hp" => 5,
              "armor" => 3,
              "firepower" => 1
            },
            nil,
            nil,
            nil
          ]
        },
        opponent_id.to_s => {
          "hand" => [],
          "deck" => [],
          "graveyard" => [],
          "empty_deck_draw_attempts" => 0,
          "platoons" => [nil, nil, nil, nil]
        }
      },
      "field" => [
        [
          {
            "type" => "headquarters",
            "player_id" => player_id,
            "hp" => 20
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
      count: 2
    )

    assert result.success?, result.error

    player = result.state["players"][player_id.to_s]
    platoon = player["platoons"][0]
    headquarters = result.state["field"][0][0]

    # Две попытки: 1 + 2 = 3 урона.
    assert_equal 2, player["empty_deck_draw_attempts"]

    # Взвод поглотил весь урон.
    assert_equal 2, platoon["hp"]

    # Штаб не получил урона.
    assert_equal 20, headquarters["hp"]

    # Партия продолжается.
    assert_equal "started", result.state["status"]

    damage_events = result.events.select do |event|
      event[:type] == "damage_applied"
    end

    assert_equal 2, damage_events.size

    assert_equal 0, damage_events[0][:headquarters_damage]
    assert_equal 1, damage_events[0][:armor_absorbed]

    assert_equal 0, damage_events[1][:headquarters_damage]
    assert_equal 2, damage_events[1][:armor_absorbed]

    platoon_events = result.events.select do |event|
      event[:type] == "platoon_damaged"
    end

    assert_equal 2, platoon_events.size
  end

  test "empty deck damage destroys platoon before damaging headquarters" do
    player_id = 1
    opponent_id = 2

    state = {
      "status" => "started",
      "players" => {
        player_id.to_s => {
          "hand" => [],
          "deck" => [],
          "graveyard" => [],
          "empty_deck_draw_attempts" => 2,
          "platoons" => [
            {
              "type" => "platoon",
              "player_id" => player_id,
              "card_id" => 100,
              "name" => "Defensive Platoon",
              "hp" => 2,
              "armor" => 2,
              "firepower" => 1
            },
            nil,
            nil,
            nil
          ]
        },
        opponent_id.to_s => {
          "hand" => [],
          "deck" => [],
          "graveyard" => [],
          "empty_deck_draw_attempts" => 0,
          "platoons" => [nil, nil, nil, nil]
        }
      },
      "field" => [
        [
          {
            "type" => "headquarters",
            "player_id" => player_id,
            "hp" => 20
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

    player = result.state["players"][player_id.to_s]
    headquarters = result.state["field"][0][0]

    # Третья попытка наносит 3 урона.
    assert_equal 3, player["empty_deck_draw_attempts"]

    # Взвод поглотил 2 урона и уничтожен.
    assert_nil player["platoons"][0]

    # Уничтоженный взвод отправлен на кладбище.
    assert_equal 1, player["graveyard"].size
    assert_equal 100, player["graveyard"][0]["card_id"]

    # Оставшийся 1 урон получил штаб.
    assert_equal 19, headquarters["hp"]

    damage_event = result.events.find do |event|
      event[:type] == "damage_applied"
    end

    assert_equal 3, damage_event[:incoming_damage]
    assert_equal 2, damage_event[:armor_absorbed]
    assert_equal 1, damage_event[:headquarters_damage]

    destroyed_event = result.events.find do |event|
      event[:type] == "platoon_destroyed"
    end

    assert_not_nil destroyed_event

    # Партия продолжается.
    assert_equal "started", result.state["status"]
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
