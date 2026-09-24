require "test_helper"

class GamesControllerTest < ActionDispatch::IntegrationTest
  test "returns forbidden when player does not belong to game" do
    game = Game.create!
    player_one = Player.create!
    player_two = Player.create!

    nation = Nation.create!(
      name: "Test Nation",
      code: "test_nation"
    )

    headquarters_card = Card.create!(
      nation: nation,
      name: "Test HQ",
      code: "test_hq",
      card_type: "headquarters",
      weight: 1,
      price: nil
    )

    deck = Deck.create!(
      player: player_one,
      nation: nation,
      name: "Test Deck"
    )

    GamePlayer.create!(
      game: game,
      player: player_one,
      nation: nation,
      deck: deck,
      headquarters_card: headquarters_card
    )

    get game_path(game, player_id: player_two.id)

    assert_response :forbidden
  end

  test "returns forbidden when player id is missing" do
    game = Game.create!

    get game_path(game)

    assert_response :forbidden
  end

  test "allows a player who belongs to the game" do
    game = Game.create!
    player = Player.create!

    nation = Nation.create!(
      name: "Test Nation",
      code: "test_nation"
    )

    headquarters_card = Card.create!(
      nation: nation,
      name: "Test HQ",
      code: "test_hq",
      card_type: "headquarters",
      weight: 1,
      price: nil
    )

    deck = Deck.create!(
      player: player,
      nation: nation,
      name: "Test Deck"
    )

    GamePlayer.create!(
      game: game,
      player: player,
      nation: nation,
      deck: deck,
      headquarters_card: headquarters_card
    )

    game.update!(
      state: {
        "status" => "waiting",
        "turn_number" => 1,
        "current_player_id" => player.id,
        "players" => {
          player.id.to_s => {
            "nation_id" => nation.id,
            "hand" => [],
            "deck" => [],
            "graveyard" => [],
            "platoons" => [nil, nil, nil, nil],
            "resources" => 0,
            "remaining_time" => 600,
            "empty_deck_draw_attempts" => 0
          }
        },
        "field" => GameEngine::GameState.empty_field
      }
    )

    get game_path(game, player_id: player.id)

    assert_not_equal 403, response.status
  end

  test "moves player's technique through controller" do
    game = Game.create!
    player = Player.create!

    nation = Nation.create!(
      name: "Move Test Nation",
      code: "move_test_nation"
    )

    headquarters_card = Card.create!(
      nation: nation,
      name: "Move Test HQ",
      code: "move_test_hq",
      card_type: "headquarters",
      weight: 1,
      price: nil
    )

    deck = Deck.create!(
      player: player,
      nation: nation,
      name: "Move Test Deck"
    )

    GamePlayer.create!(
      game: game,
      player: player,
      nation: nation,
      deck: deck,
      headquarters_card: headquarters_card
    )

    field = GameEngine::GameState.empty_field

    field[1][1] = {
      "type" => "technique",
      "card_id" => 15,
      "player_id" => player.id.to_s,
      "technique_type" => "medium_tank",
      "hp" => 10,
      "firepower" => 4,
      "fuel" => 2,
      "attack_range" => 1,
      "movement_count" => 1,
      "movement_type" => "diagonal",
      "has_attacked" => false,
      "has_counterattacked" => false
    }

    game.update!(
      state: {
        "status" => "started",
        "turn_number" => 1,
        "current_player_id" => player.id,
        "turn_started_at" => Time.current.iso8601,
        "players" => {
          player.id.to_s => {
            "nation_id" => nation.id,
            "hand" => [],
            "deck" => [],
            "graveyard" => [],
            "platoons" => [nil, nil, nil, nil],
            "resources" => 0,
            "remaining_time" => 600,
            "empty_deck_draw_attempts" => 0
          }
        },
        "field" => field
      }
    )

    post move_path(
      game,
      player_id: player.id,
      from_row: 1,
      from_column: 1,
      to_row: 0,
      to_column: 2
    )

    assert_response :redirect

    game.reload

    assert_nil game.state["field"][1][1]
    assert_equal "technique", game.state["field"][0][2]["type"]
    assert_equal player.id.to_s, game.state["field"][0][2]["player_id"]
    assert_equal 0, game.state["field"][0][2]["movement_count"]
  end

  test "returns unprocessable entity when move is invalid" do
    game = Game.create!
    player = Player.create!

    nation = Nation.create!(
      name: "Invalid Move Nation",
      code: "invalid_move_nation"
    )

    headquarters_card = Card.create!(
      nation: nation,
      name: "Invalid Move HQ",
      code: "invalid_move_hq",
      card_type: "headquarters",
      weight: 1,
      price: nil
    )

    deck = Deck.create!(
      player: player,
      nation: nation,
      name: "Invalid Move Deck"
    )

    GamePlayer.create!(
      game: game,
      player: player,
      nation: nation,
      deck: deck,
      headquarters_card: headquarters_card
    )

    field = GameEngine::GameState.empty_field

    field[1][1] = {
      "type" => "technique",
      "card_id" => 15,
      "player_id" => player.id.to_s,
      "technique_type" => "medium_tank",
      "hp" => 10,
      "firepower" => 4,
      "fuel" => 2,
      "attack_range" => 1,
      "movement_count" => 1,
      "movement_type" => "diagonal",
      "has_attacked" => false,
      "has_counterattacked" => false
    }

    original_field = field.deep_dup

    game.update!(
      state: {
        "status" => "started",
        "turn_number" => 1,
        "current_player_id" => player.id,
        "turn_started_at" => Time.current.iso8601,
        "players" => {
          player.id.to_s => {
            "nation_id" => nation.id,
            "hand" => [],
            "deck" => [],
            "graveyard" => [],
            "platoons" => [nil, nil, nil, nil],
            "resources" => 0,
            "remaining_time" => 600,
            "empty_deck_draw_attempts" => 0
          }
        },
        "field" => field
      }
    )

    post move_path(
      game,
      player_id: player.id,
      from_row: 1,
      from_column: 1,
      to_row: 0,
      to_column: 3
    )

    assert_response :unprocessable_entity
    assert_equal "Invalid movement", response.body

    game.reload

    assert_equal original_field, game.state["field"]
  end
  
  test "attacks player's technique through controller" do
    game = Game.create!
    player = Player.create!
    enemy = Player.create!

    nation = Nation.create!(
      name: "Attack Test Nation",
      code: "attack_test_nation"
    )

    enemy_nation = Nation.create!(
      name: "Enemy Attack Test Nation",
      code: "enemy_attack_test_nation"
    )

    headquarters_card = Card.create!(
      nation: nation,
      name: "Attack Test HQ",
      code: "attack_test_hq",
      card_type: "headquarters",
      weight: 1,
      price: nil
    )

    enemy_headquarters_card = Card.create!(
      nation: enemy_nation,
      name: "Enemy Attack Test HQ",
      code: "enemy_attack_test_hq",
      card_type: "headquarters",
      weight: 1,
      price: nil
    )

    deck = Deck.create!(
      player: player,
      nation: nation,
      name: "Attack Test Deck"
    )

    enemy_deck = Deck.create!(
      player: enemy,
      nation: enemy_nation,
      name: "Enemy Attack Test Deck"
    )

    GamePlayer.create!(
      game: game,
      player: player,
      nation: nation,
      deck: deck,
      headquarters_card: headquarters_card
    )

    GamePlayer.create!(
      game: game,
      player: enemy,
      nation: enemy_nation,
      deck: enemy_deck,
      headquarters_card: enemy_headquarters_card
    )

    field = GameEngine::GameState.empty_field

    field[1][1] = {
      "type" => "technique",
      "card_id" => 15,
      "player_id" => player.id.to_s,
      "technique_type" => "medium_tank",
      "hp" => 10,
      "firepower" => 4,
      "fuel" => 2,
      "attack_range" => 1,
      "movement_count" => 1,
      "movement_type" => "diagonal",
      "has_attacked" => false,
      "has_counterattacked" => false
    }

    field[1][2] = {
      "type" => "technique",
      "card_id" => 16,
      "player_id" => enemy.id.to_s,
      "technique_type" => "medium_tank",
      "hp" => 10,
      "firepower" => 3,
      "fuel" => 2,
      "attack_range" => 1,
      "movement_count" => 1,
      "movement_type" => "diagonal",
      "has_attacked" => false,
      "has_counterattacked" => false
    }

    game.update!(
      state: {
        "status" => "started",
        "turn_number" => 1,
        "current_player_id" => player.id,
        "turn_started_at" => Time.current.iso8601,
        "players" => {
          player.id.to_s => {
            "nation_id" => nation.id,
            "hand" => [],
            "deck" => [],
            "graveyard" => [],
            "platoons" => [nil, nil, nil, nil],
            "resources" => 0,
            "remaining_time" => 600,
            "empty_deck_draw_attempts" => 0
          },
          enemy.id.to_s => {
            "nation_id" => enemy_nation.id,
            "hand" => [],
            "deck" => [],
            "graveyard" => [],
            "platoons" => [nil, nil, nil, nil],
            "resources" => 0,
            "remaining_time" => 600,
            "empty_deck_draw_attempts" => 0
          }
        },
        "field" => field
      }
    )

    post attack_path(
      game,
      player_id: player.id,
      attacker_row: 1,
      attacker_column: 1,
      target_row: 1,
      target_column: 2
    )

    assert_response :redirect

    game.reload

    attacker = game.state["field"][1][1]
    target = game.state["field"][1][2]

    assert_equal 7, attacker["hp"]
    assert_equal 6, target["hp"]
    assert_equal true, attacker["has_attacked"]
    assert_equal true, target["has_counterattacked"]
  end

	test "returns unprocessable entity when attack is invalid" do
		game = Game.create!
		player = Player.create!
		enemy = Player.create!

		nation = Nation.create!(
		  name: "Invalid Attack Nation",
		  code: "invalid_attack_nation"
		)

		enemy_nation = Nation.create!(
		  name: "Invalid Enemy Attack Nation",
		  code: "invalid_enemy_attack_nation"
		)

		headquarters_card = Card.create!(
		  nation: nation,
		  name: "Invalid Attack HQ",
		  code: "invalid_attack_hq",
		  card_type: "headquarters",
		  weight: 1,
		  price: nil
		)

		enemy_headquarters_card = Card.create!(
		  nation: enemy_nation,
		  name: "Invalid Enemy Attack HQ",
		  code: "invalid_enemy_attack_hq",
		  card_type: "headquarters",
		  weight: 1,
		  price: nil
		)

		deck = Deck.create!(
		  player: player,
		  nation: nation,
		  name: "Invalid Attack Deck"
		)

		enemy_deck = Deck.create!(
		  player: enemy,
		  nation: enemy_nation,
		  name: "Invalid Enemy Attack Deck"
		)

		GamePlayer.create!(
		  game: game,
		  player: player,
		  nation: nation,
		  deck: deck,
		  headquarters_card: headquarters_card
		)

		GamePlayer.create!(
		  game: game,
		  player: enemy,
		  nation: enemy_nation,
		  deck: enemy_deck,
		  headquarters_card: enemy_headquarters_card
		)

		field = GameEngine::GameState.empty_field

		field[1][1] = {
		  "type" => "technique",
		  "card_id" => 15,
		  "player_id" => player.id.to_s,
		  "technique_type" => "medium_tank",
		  "hp" => 10,
		  "firepower" => 4,
		  "fuel" => 2,
		  "attack_range" => 1,
		  "movement_count" => 1,
		  "movement_type" => "diagonal",
		  "has_attacked" => false,
		  "has_counterattacked" => false
		}

		field[1][2] = {
		  "type" => "technique",
		  "card_id" => 16,
		  "player_id" => enemy.id.to_s,
		  "technique_type" => "medium_tank",
		  "hp" => 10,
		  "firepower" => 3,
		  "fuel" => 2,
		  "attack_range" => 1,
		  "movement_count" => 1,
		  "movement_type" => "diagonal",
		  "has_attacked" => false,
		  "has_counterattacked" => false
		}

		field[0][4] = {
		  "type" => "technique",
		  "card_id" => 17,
		  "player_id" => enemy.id.to_s,
		  "technique_type" => "medium_tank",
		  "hp" => 10,
		  "firepower" => 3,
		  "fuel" => 2,
		  "attack_range" => 1,
		  "movement_count" => 1,
		  "movement_type" => "diagonal",
		  "has_attacked" => false,
		  "has_counterattacked" => false
		}

		original_field = field.deep_dup

		game.update!(
		  state: {
		    "status" => "started",
		    "turn_number" => 1,
		    "current_player_id" => player.id,
		    "turn_started_at" => Time.current.iso8601,
		    "players" => {
		      player.id.to_s => {
		        "nation_id" => nation.id,
		        "hand" => [],
		        "deck" => [],
		        "graveyard" => [],
		        "platoons" => [nil, nil, nil, nil],
		        "resources" => 0,
		        "remaining_time" => 600,
		        "empty_deck_draw_attempts" => 0
		      },
		      enemy.id.to_s => {
		        "nation_id" => enemy_nation.id,
		        "hand" => [],
		        "deck" => [],
		        "graveyard" => [],
		        "platoons" => [nil, nil, nil, nil],
		        "resources" => 0,
		        "remaining_time" => 600,
		        "empty_deck_draw_attempts" => 0
		      }
		    },
		    "field" => field
		  }
		)

		post attack_path(
		  game,
		  player_id: player.id,
		  attacker_row: 1,
		  attacker_column: 1,
		  target_row: 0,
		  target_column: 4
		)

		assert_response :unprocessable_entity
		assert_equal "Invalid attack range", response.body

		game.reload

		assert_equal original_field, game.state["field"]
	end

  test "returns forbidden when player does not belong to game during attack" do
    game = Game.create!
    player = Player.create!
    outsider = Player.create!

    nation = Nation.create!(
      name: "Forbidden Attack Nation",
      code: "forbidden_attack_nation"
    )

    headquarters_card = Card.create!(
      nation: nation,
      name: "Forbidden Attack HQ",
      code: "forbidden_attack_hq",
      card_type: "headquarters",
      weight: 1,
      price: nil
    )

    deck = Deck.create!(
      player: player,
      nation: nation,
      name: "Forbidden Attack Deck"
    )

    GamePlayer.create!(
      game: game,
      player: player,
      nation: nation,
      deck: deck,
      headquarters_card: headquarters_card
    )

    post attack_path(
      game,
      player_id: outsider.id,
      attacker_row: 1,
      attacker_column: 1,
      target_row: 1,
      target_column: 2
    )

    assert_response :forbidden
  end
end
