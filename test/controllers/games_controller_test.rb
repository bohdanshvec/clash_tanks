require "test_helper"

class GamesControllerTest < ActionDispatch::IntegrationTest
  def log_in(player)
    post login_path, params: {
      email: player.email,
      password: "password"
    }
  end

  test "returns forbidden when player does not belong to game" do
    game = Game.create!
    player_one = create_player
    player_two = create_player

    nation = Nation.create!(
      name: "Test Nation",
      code: "test_nation"
    )

    headquarters_card = Card.create!(
      nation: nation,
      name: "Test HQ",
      code: "test_hq_#{SecureRandom.hex(4)}",
      card_type: "headquarters",
      weight: 1,
      price: nil
    )

    deck = Deck.create!(
      player: player_one,
      nation: nation,
      name: "Test Deck",
      headquarters_card: headquarters_card
    )

    GamePlayer.create!(
      game: game,
      player: player_one,
      nation: nation,
      deck: deck,
      headquarters_card: headquarters_card
    )

    log_in(player_two)

    get game_path(game)

    assert_response :forbidden
  end

  test "returns forbidden when player id is missing" do
    game = Game.create!

    get game_path(game)

    assert_response :forbidden
  end

  test "allows a player who belongs to the game" do
    game = Game.create!
    player = create_player

    nation = Nation.create!(
      name: "Test Nation",
      code: "test_nation"
    )

    headquarters_card = Card.create!(
      nation: nation,
      name: "Test HQ",
      code: "test_hq_#{SecureRandom.hex(4)}",
      card_type: "headquarters",
      weight: 1,
      price: nil
    )

    deck = Deck.create!(
      player: player,
      nation: nation,
      name: "Test Deck",
      headquarters_card: headquarters_card
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

    log_in(player)

    get game_path(game)

    assert_not_equal 403, response.status
  end

  test "moves player's technique through controller" do
    game = Game.create!
    player = create_player

    nation = Nation.create!(
      name: "Move Test Nation",
      code: "move_test_nation"
    )

    headquarters_card = Card.create!(
      nation: nation,
      name: "Move Test HQ",
      code: "move_test_hq_#{SecureRandom.hex(4)}",
      card_type: "headquarters",
      weight: 1,
      price: nil
    )

    deck = Deck.create!(
      player: player,
      nation: nation,
      name: "Move Test Deck",
      headquarters_card: headquarters_card
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

    log_in(player)

    post move_path(
      game,
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
    player = create_player

    nation = Nation.create!(
      name: "Invalid Move Nation",
      code: "invalid_move_nation"
    )

    headquarters_card = Card.create!(
      nation: nation,
      name: "Invalid Move HQ",
      code: "invalid_move_hq_#{SecureRandom.hex(4)}",
      card_type: "headquarters",
      weight: 1,
      price: nil
    )

    deck = Deck.create!(
      player: player,
      nation: nation,
      name: "Invalid Move Deck",
      headquarters_card: headquarters_card
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

    log_in(player)

    post move_path(
      game,
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
    player = create_player
    enemy = create_player

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
      code: "attack_test_hq_#{SecureRandom.hex(4)}",
      card_type: "headquarters",
      weight: 1,
      price: nil
    )

    enemy_headquarters_card = Card.create!(
      nation: enemy_nation,
      name: "Enemy Attack Test HQ",
      code: "enemy_attack_test_hq_#{SecureRandom.hex(4)}",
      card_type: "headquarters",
      weight: 1,
      price: nil
    )

    deck = Deck.create!(
      player: player,
      nation: nation,
      name: "Attack Test Deck",
      headquarters_card: headquarters_card
    )

    enemy_deck = Deck.create!(
      player: enemy,
      nation: enemy_nation,
      name: "Enemy Attack Test Deck",
      headquarters_card: enemy_headquarters_card
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

    log_in(player)

    post attack_path(
      game,
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
  
test "finishes game when attack destroys headquarters through controller" do
  game = Game.create!
  player = create_player
  enemy = create_player

  nation = Nation.create!(
    name: "HQ Attack Test Nation",
    code: "hq_attack_test_nation"
  )

  enemy_nation = Nation.create!(
    name: "Enemy HQ Attack Test Nation",
    code: "enemy_hq_attack_test_nation"
  )

  headquarters_card = Card.create!(
    nation: nation,
    name: "HQ Attack Test HQ",
    code: "hq_attack_test_hq_#{SecureRandom.hex(4)}",
    card_type: "headquarters",
    weight: 1,
    price: nil
  )

  enemy_headquarters_card = Card.create!(
    nation: enemy_nation,
    name: "Enemy HQ Attack Test HQ",
    code: "enemy_hq_attack_test_hq_#{SecureRandom.hex(4)}",
    card_type: "headquarters",
    weight: 1,
    price: nil
  )

  deck = Deck.create!(
    player: player,
    nation: nation,
    name: "HQ Attack Test Deck",
    headquarters_card: headquarters_card
  )

  enemy_deck = Deck.create!(
    player: enemy,
    nation: enemy_nation,
    name: "Enemy HQ Attack Test Deck",
    headquarters_card: enemy_headquarters_card
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

  state = GameEngine::GameState.initial(
    current_player_id: player.id,
		participants: [
			headquarters_participant(
				player_id: player.id,
				nation_id: nation.id
			),
			headquarters_participant(
				player_id: enemy.id,
				nation_id: enemy_nation.id
			)
		]
  )

  state["current_player_id"] = player.id.to_s

  enemy_hq = state["field"][0][4]
  enemy_hq["hp"] = 1

  game.update!(
    state: state
  )

  log_in(player)

  post attack_path(
    game,
    attacker_row: 2,
    attacker_column: 0,
    target_row: 0,
    target_column: 4
  )

  assert_response :redirect

  game.reload

  assert game.finished?
  assert_equal "finished", game.state["status"]

  assert_equal(
    {
      "winner_id" => player.id,
      "loser_id" => enemy.id,
      "reason" => "headquarters_destroyed"
    },
    game.state["result"]
  )

  player_actions = GameEngine::AvailableActions.call(
    state: game.state,
    player_id: player.id.to_s
  )

  enemy_actions = GameEngine::AvailableActions.call(
    state: game.state,
    player_id: enemy.id.to_s
  )

  assert_empty player_actions["field"]
  assert_empty player_actions["hand"]

  assert_empty enemy_actions["field"]
  assert_empty enemy_actions["hand"]

  finished_state = game.state.deep_dup

  post attack_path(
    game,
    attacker_row: 2,
    attacker_column: 0,
    target_row: 0,
    target_column: 4
  )

  assert_response :unprocessable_entity

  game.reload

  assert_equal finished_state, game.state
  assert game.finished?
  assert_equal "headquarters_destroyed", game.state["result"]["reason"]
end

  test "returns unprocessable entity when attack is invalid" do
    game = Game.create!
    player = create_player
    enemy = create_player

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
      code: "invalid_attack_hq_#{SecureRandom.hex(4)}",
      card_type: "headquarters",
      weight: 1,
      price: nil
    )

    enemy_headquarters_card = Card.create!(
      nation: enemy_nation,
      name: "Invalid Enemy Attack HQ",
      code: "invalid_enemy_attack_hq_#{SecureRandom.hex(4)}",
      card_type: "headquarters",
      weight: 1,
      price: nil
    )

    deck = Deck.create!(
      player: player,
      nation: nation,
      name: "Invalid Attack Deck",
      headquarters_card: headquarters_card
    )

    enemy_deck = Deck.create!(
      player: enemy,
      nation: enemy_nation,
      name: "Invalid Enemy Attack Deck",
      headquarters_card: enemy_headquarters_card
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

    log_in(player)

    post attack_path(
      game,
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
    player = create_player
    outsider = create_player

    nation = Nation.create!(
      name: "Forbidden Attack Nation",
      code: "forbidden_attack_nation"
    )

    headquarters_card = Card.create!(
      nation: nation,
      name: "Forbidden Attack HQ",
      code: "forbidden_attack_hq_#{SecureRandom.hex(4)}",
      card_type: "headquarters",
      weight: 1,
      price: nil
    )

    deck = Deck.create!(
      player: player,
      nation: nation,
      name: "Forbidden Attack Deck",
      headquarters_card: headquarters_card
    )

    GamePlayer.create!(
      game: game,
      player: player,
      nation: nation,
      deck: deck,
      headquarters_card: headquarters_card
    )

    log_in(outsider)

    post attack_path(
      game,
      attacker_row: 1,
      attacker_column: 1,
      target_row: 1,
      target_column: 2
    )

    assert_response :forbidden
  end

	test "surrenders game through controller" do
		game = Game.create!
		player = create_player
		enemy = create_player

		nation = Nation.create!(
		  name: "Surrender Test Nation",
		  code: "surrender_test_nation"
		)

		enemy_nation = Nation.create!(
		  name: "Enemy Surrender Test Nation",
		  code: "enemy_surrender_test_nation"
		)

		headquarters_card = Card.create!(
		  nation: nation,
		  name: "Surrender Test HQ",
		  code: "surrender_test_hq_#{SecureRandom.hex(4)}",
		  card_type: "headquarters",
		  weight: 1,
		  price: nil
		)

		enemy_headquarters_card = Card.create!(
		  nation: enemy_nation,
		  name: "Enemy Surrender Test HQ",
		  code: "enemy_surrender_test_hq_#{SecureRandom.hex(4)}",
		  card_type: "headquarters",
		  weight: 1,
		  price: nil
		)

		deck = Deck.create!(
		  player: player,
		  nation: nation,
		  name: "Surrender Test Deck",
		  headquarters_card: headquarters_card
		)

		enemy_deck = Deck.create!(
		  player: enemy,
		  nation: enemy_nation,
		  name: "Enemy Surrender Test Deck",
		  headquarters_card: enemy_headquarters_card
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

		game.update!(
		  state: {
		    "status" => "started",
		    "turn_number" => 1,
		    "current_player_id" => enemy.id,
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
		    "field" => GameEngine::GameState.empty_field
		  }
		)

		log_in(player)

		post surrender_path(game)

		assert_response :redirect

		game.reload

		assert game.finished?
		assert_equal "finished", game.state["status"]

		assert_equal(
		  {
		    "winner_id" => enemy.id.to_s,
		    "loser_id" => player.id.to_s,
		    "reason" => "surrender"
		  },
		  game.state["result"]
		)

		player_actions = GameEngine::AvailableActions.call(
		  state: game.state,
		  player_id: player.id.to_s
		)

		enemy_actions = GameEngine::AvailableActions.call(
		  state: game.state,
		  player_id: enemy.id.to_s
		)

		assert_empty player_actions["field"]
		assert_empty player_actions["hand"]

		assert_empty enemy_actions["field"]
		assert_empty enemy_actions["hand"]

		finished_state = game.state.deep_dup

		post surrender_path(game)

		assert_response :unprocessable_entity

		game.reload

		assert_equal finished_state, game.state
		assert game.finished?
		assert_equal "surrender", game.state["result"]["reason"]
	end

  test "player can create a waiting pvp game with a complete deck" do
    player = create_player
    deck = create_complete_deck(player: player)

    post login_path, params: {
      email: player.email,
      password: "password"
    }

    assert_difference("Game.count", 1) do
      assert_difference("GamePlayer.count", 1) do
        post games_path, params: {
          deck_id: deck.id,
          mode: "pvp"
        }
      end
    end

    game = Game.order(:id).last

    assert_redirected_to game_path(game)
    assert game.waiting?
    assert_nil game.state

    game_player = game.game_players.first

    assert_equal player, game_player.player
    assert_equal deck, game_player.deck
    assert_equal deck.nation, game_player.nation
    assert_equal deck.headquarters_card, game_player.headquarters_card
  end

  test "player cannot create a game with another player's deck" do
    player = create_player
    other_player = create_player(email: "other@example.com")

    deck = create_complete_deck(player: other_player)

    post login_path, params: {
      email: player.email,
      password: "password"
    }

    assert_no_difference("Game.count") do
      post games_path, params: {
        deck_id: deck.id,
        mode: "pvp"
      }
    end

    assert_response :not_found
  end

  test "player cannot create a game with an incomplete deck" do
    player = create_player

    nation = Nation.create!(
      name: "Incomplete Nation",
      code: "incomplete_#{SecureRandom.hex(4)}"
    )

    headquarters_card = create_headquarters_card(nation: nation)

    deck = Deck.create!(
      player: player,
      nation: nation,
      name: "Incomplete Deck",
      headquarters_card: headquarters_card
    )

    9.times do |index|
      card = Card.create!(
        code: "#{nation.code}_card_#{index}_#{SecureRandom.hex(4)}",
        nation: nation,
        name: "Test Card #{index}",
        card_type: "order",
        weight: 1,
        price: 1
      )

      DeckCard.create!(
        deck: deck,
        card: card,
        quantity: 1
      )
    end

    assert_not deck.complete?

    post login_path, params: {
      email: player.email,
      password: "password"
    }

    assert_no_difference("Game.count") do
      post games_path, params: {
        deck_id: deck.id,
        mode: "pvp"
      }
    end

    assert_response :unprocessable_entity
  end

  test "joins an existing compatible waiting game and starts a complete game state" do
    first_player = create_player
    second_player = create_player(email: "second@example.com")

    first_deck = create_complete_deck(player: first_player)
    second_deck = create_complete_deck(player: second_player)

    waiting_game = Game.create!(
      status: "waiting",
      state: nil
    )

    waiting_game.game_players.create!(
      player: first_player,
      nation: first_deck.nation,
      deck: first_deck,
      headquarters_card: first_deck.headquarters_card
    )

    post login_path, params: {
      email: second_player.email,
      password: "password"
    }

    assert_no_difference("Game.count") do
      post games_path, params: {
        deck_id: second_deck.id,
        mode: "pvp"
      }
    end

    waiting_game.reload

    assert waiting_game.started?
    assert_not_nil waiting_game.state
    assert_equal 2, waiting_game.game_players.count
    assert_redirected_to game_path(waiting_game)

    state = waiting_game.state

    assert_equal "started", state["status"]
    assert_equal 1, state["turn_number"]

    assert_includes(
      [first_player.id.to_s, second_player.id.to_s],
      state["current_player_id"].to_s
    )

    assert_equal(
      [first_player.id.to_s, second_player.id.to_s].sort,
      state["players"].keys.sort
    )

    assert_equal(
      first_deck.nation_id,
      state["players"][first_player.id.to_s]["nation_id"]
    )

    assert_equal(
      second_deck.nation_id,
      state["players"][second_player.id.to_s]["nation_id"]
    )

    assert_equal 6, state["players"][first_player.id.to_s]["hand"].size
    assert_equal 6, state["players"][second_player.id.to_s]["hand"].size

    assert_equal 4, state["players"][first_player.id.to_s]["deck"].size
    assert_equal 4, state["players"][second_player.id.to_s]["deck"].size

    assert_equal(
      [2, 0],
      find_object_coordinates(state, "headquarters", first_player.id.to_s)
    )

    assert_equal(
      [0, 4],
      find_object_coordinates(state, "headquarters", second_player.id.to_s)
    )
  end
  
  test "completes full pvp lifecycle from play to first action" do
    first_player = create_player
    second_player = create_player(email: "second@example.com")

    first_deck = create_complete_deck(player: first_player)
    second_deck = create_complete_deck(player: second_player)

    # Player 1 входит в игру через /play.
    post login_path, params: {
      email: first_player.email,
      password: "password"
    }

    get play_path

    assert_response :success

    # Player 1 создаёт waiting game.
    assert_difference("Game.count", 1) do
      assert_difference("GamePlayer.count", 1) do
        post games_path, params: {
          deck_id: first_deck.id,
          mode: "pvp"
        }
      end
    end

    waiting_game = Game.order(:id).last

    assert_redirected_to game_path(waiting_game)
    assert waiting_game.waiting?
    assert_nil waiting_game.state

    assert_equal 1, waiting_game.game_players.count
    assert_equal first_player.id, waiting_game.game_players.first.player_id

    # Player 2 входит в игру через /play.
    post login_path, params: {
      email: second_player.email,
      password: "password"
    }

    get play_path

    assert_response :success

    # Player 2 выбирает совместимую колоду.
    assert_no_difference("Game.count") do
      assert_difference("GamePlayer.count", 1) do
        post games_path, params: {
          deck_id: second_deck.id,
          mode: "pvp"
        }
      end
    end

    waiting_game.reload

    # Waiting → started.
    assert waiting_game.started?
    assert_not_nil waiting_game.state
    assert_equal 2, waiting_game.game_players.count

    assert_redirected_to game_path(waiting_game)

    state = waiting_game.state

    assert_equal "started", state["status"]
    assert_equal 1, state["turn_number"]
    assert_equal 2, state["players"].size
    assert_equal 3, state["field"].size
    assert state["field"].all? { |row| row.size == 5 }

    assert_includes(
      [first_player.id.to_s, second_player.id.to_s],
      state["current_player_id"].to_s
    )

    assert state["turn_started_at"].present?

    # Оба игрока получили полную структуру GameState.
    [first_player, second_player].each do |player|
      player_state = state["players"][player.id.to_s]

      assert_not_nil player_state
      assert player_state.key?("nation_id")
      assert player_state.key?("hand")
      assert player_state.key?("deck")
      assert player_state.key?("graveyard")
      assert player_state.key?("platoons")
      assert player_state.key?("resources")
      assert player_state.key?("remaining_time")
      assert player_state.key?("empty_deck_draw_attempts")

      assert_equal 6, player_state["hand"].size
      assert_equal 4, player_state["deck"].size
      assert_empty player_state["graveyard"]
      assert_equal 4, player_state["platoons"].size
      assert_equal 600, player_state["remaining_time"]
      assert_equal 0, player_state["empty_deck_draw_attempts"]
    end

    # Оба штаба находятся на своих логических координатах.
    assert_equal(
      [2, 0],
      find_object_coordinates(state, "headquarters", first_player.id.to_s)
    )

    assert_equal(
      [0, 4],
      find_object_coordinates(state, "headquarters", second_player.id.to_s)
    )

    # Второй игрок открывает уже started game.
    get game_path(waiting_game)

    assert_response :success

    # VisibleState не должен раскрывать закрытую информацию второго игрока.
    assert_select "[data-player-id='#{second_player.id}']"

    # Возвращаем session к игроку, чей сейчас ход.
    current_player = Player.find(state["current_player_id"])

    log_in(current_player)

    # Первый Action после запуска игры.
    post end_turn_path(waiting_game)

    assert_response :redirect

    waiting_game.reload

    assert waiting_game.started?
    assert_not_nil waiting_game.state

    assert_equal 2, waiting_game.state["turn_number"]
    assert_not_equal(
      current_player.id.to_s,
      waiting_game.state["current_player_id"].to_s
    )
  end
  
  test "rejects play card while game is waiting" do
    player = create_player
    deck = create_complete_deck(player: player)

    game = Game.create!(status: "waiting")

    game.game_players.create!(
      player: player,
      nation: deck.nation,
      deck: deck,
      headquarters_card: deck.headquarters_card
    )

    log_in(player)

    post play_card_path(game), params: {
      card_id: "1",
      row: 1,
      column: 1
    }

    assert_response :unprocessable_entity
    assert_equal "Game has not started", response.body
    assert_nil game.reload.state
  end

  test "rejects move while game is waiting" do
    player = create_player
    deck = create_complete_deck(player: player)

    game = Game.create!(status: "waiting")

    game.game_players.create!(
      player: player,
      nation: deck.nation,
      deck: deck,
      headquarters_card: deck.headquarters_card
    )

    log_in(player)

    post move_path(game), params: {
      from_row: 1,
      from_column: 1,
      to_row: 1,
      to_column: 2
    }

    assert_response :unprocessable_entity
    assert_equal "Game has not started", response.body
    assert_nil game.reload.state
  end

  test "rejects surrender while game is waiting" do
    player = create_player
    deck = create_complete_deck(player: player)

    game = Game.create!(status: "waiting")

    game.game_players.create!(
      player: player,
      nation: deck.nation,
      deck: deck,
      headquarters_card: deck.headquarters_card
    )

    log_in(player)

    post surrender_path(game)

    assert_response :unprocessable_entity
    assert_equal "Game has not started", response.body
    assert_nil game.reload.state
  end

  test "forbids a non-participant from performing an action in a waiting game" do
    player = create_player
    outsider = create_player(email: "outsider@example.com")
    deck = create_complete_deck(player: player)

    game = Game.create!(status: "waiting")

    game.game_players.create!(
      player: player,
      nation: deck.nation,
      deck: deck,
      headquarters_card: deck.headquarters_card
    )

    log_in(outsider)

    post surrender_path(game)

    assert_response :forbidden
    assert_nil game.reload.state
  end

  test "rejects end turn while game is waiting" do
    player = create_player
    deck = create_complete_deck(player: player)

    game = Game.create!(
      status: "waiting",
      state: nil
    )

    game.game_players.create!(
      player: player,
      nation: deck.nation,
      deck: deck,
      headquarters_card: deck.headquarters_card
    )

    log_in(player)

    assert_no_difference("Game.count") do
      post end_turn_path(game)
    end

    assert_response :unprocessable_entity

    game.reload

    assert game.waiting?
    assert_nil game.state
  end

  test "rejects attack while game is waiting" do
    player = create_player
    enemy = create_player(email: "enemy@example.com")

    deck = create_complete_deck(player: player)
    enemy_deck = create_complete_deck(player: enemy)

    game = Game.create!(
      status: "waiting",
      state: nil
    )

    game.game_players.create!(
      player: player,
      nation: deck.nation,
      deck: deck,
      headquarters_card: deck.headquarters_card
    )

    game.game_players.create!(
      player: enemy,
      nation: enemy_deck.nation,
      deck: enemy_deck,
      headquarters_card: enemy_deck.headquarters_card
    )

    log_in(player)

    post attack_path(
      game,
      attacker_row: 1,
      attacker_column: 1,
      target_row: 1,
      target_column: 2
    )

    assert_response :unprocessable_entity

    game.reload

    assert game.waiting?
    assert_nil game.state
  end

  test "joining an existing waiting game refreshes other waiting rooms" do
    first_player = create_player
    second_player = create_player(email: "second@example.com")
    third_player = create_player(email: "third@example.com")

    first_deck = create_complete_deck(player: first_player)
    second_deck = create_complete_deck(player: second_player)
    third_deck = create_complete_deck(player: third_player)

    waiting_game = Game.create!(
      status: "waiting",
      last_seen_at: Time.current
    )

    waiting_game.game_players.create!(
      player: first_player,
      nation: first_deck.nation,
      deck: first_deck,
      headquarters_card: first_deck.headquarters_card
    )

    other_waiting_game = Game.create!(
      status: "waiting",
      last_seen_at: Time.current
    )

    other_waiting_game.game_players.create!(
      player: second_player,
      nation: second_deck.nation,
      deck: second_deck,
      headquarters_card: second_deck.headquarters_card
    )

    # Делаем третью колоду совместимой с первой.
    first_deck.deck_cards.first.card.update!(weight: 20)
    third_deck.deck_cards.first.card.update!(weight: 20)

    post login_path, params: {
      email: third_player.email,
      password: "password"
    }

    broadcasted_games = []

    original_method = Turbo::StreamsChannel.method(:broadcast_refresh_to)

    Turbo::StreamsChannel.define_singleton_method(:broadcast_refresh_to) do |game|
      broadcasted_games << game
    end

    begin
      post games_path, params: {
        deck_id: third_deck.id,
        mode: "pvp"
      }
    ensure
      Turbo::StreamsChannel.define_singleton_method(
        :broadcast_refresh_to,
        original_method
      )
    end

    waiting_game.reload
    other_waiting_game.reload

    assert waiting_game.started?
    assert_equal 2, waiting_game.game_players.count

    assert other_waiting_game.waiting?

    assert_includes broadcasted_games, waiting_game
    assert_includes broadcasted_games, other_waiting_game

    assert_redirected_to game_path(waiting_game)
  end

  test "creates a waiting game when no compatible opponent exists" do
    other_player = create_player
    other_deck = create_complete_deck(player: other_player)
		other_deck.deck_cards.first.card.update!(weight: 20)

    other_waiting_game = Game.create!(
      status: "waiting",
      last_seen_at: Time.current
    )

    other_waiting_game.game_players.create!(
      player: other_player,
      nation: other_deck.nation,
      deck: other_deck,
      headquarters_card: other_deck.headquarters_card
    )

    player = create_player(email: "new-player@example.com")
    deck = create_complete_deck(player: player)

    post login_path, params: {
      email: player.email,
      password: "password"
    }

    broadcasted_games = []

    original_method = Turbo::StreamsChannel.method(:broadcast_refresh_to)

    Turbo::StreamsChannel.define_singleton_method(:broadcast_refresh_to) do |game|
      broadcasted_games << game
    end

    begin
      assert_difference("Game.count", 1) do
        post games_path, params: {
          deck_id: deck.id,
          mode: "pvp"
        }
      end
    ensure
      Turbo::StreamsChannel.define_singleton_method(
        :broadcast_refresh_to,
        original_method
      )
    end

    game = Game.order(:id).last

    assert game.waiting?
    assert_nil game.state
    assert_equal 1, game.game_players.count
    assert other_waiting_game.waiting?

    assert_includes broadcasted_games, other_waiting_game
    assert_not_includes broadcasted_games, game

    assert_redirected_to game_path(game)
  end

  test "cancels own waiting game" do
    player = create_player
    deck = create_complete_deck(player: player)

    post login_path, params: {
      email: player.email,
      password: "password"
    }

    game = Game.create!(status: "waiting")

    game.game_players.create!(
      player: player,
      nation: deck.nation,
      deck: deck,
      headquarters_card: deck.headquarters_card
    )

    assert_difference("Game.count", -1) do
      delete cancel_waiting_game_path(game)
    end

    assert_redirected_to play_path
    assert_not Game.exists?(game.id)
  end

  test "cannot cancel another player's waiting game" do
    owner = create_player
    player = create_player(email: "second@example.com")

    deck = create_complete_deck(player: owner)

    game = Game.create!(status: "waiting")

    game.game_players.create!(
      player: owner,
      nation: deck.nation,
      deck: deck,
      headquarters_card: deck.headquarters_card
    )

    post login_path, params: {
      email: player.email,
      password: "password"
    }

    assert_no_difference("Game.count") do
      delete cancel_waiting_game_path(game)
    end

    assert_response :forbidden
    assert Game.exists?(game.id)
  end

  test "cannot cancel a started game" do
    player = create_player
    deck = create_complete_deck(player: player)

    post login_path, params: {
      email: player.email,
      password: "password"
    }

    game = Game.create!(
      status: "started",
      state: {}
    )

    game.game_players.create!(
      player: player,
      nation: deck.nation,
      deck: deck,
      headquarters_card: deck.headquarters_card
    )

    assert_no_difference("Game.count") do
      delete cancel_waiting_game_path(game)
    end

    assert_response :unprocessable_entity
    assert Game.exists?(game.id)
  end

  test "waiting heartbeat updates game last_seen_at" do
    player = create_player
    deck = create_complete_deck(player: player)

    post login_path, params: {
      email: player.email,
      password: "password"
    }

    old_time = 1.minute.ago

    game = Game.create!(
      status: "waiting",
      last_seen_at: old_time
    )

    game.game_players.create!(
      player: player,
      nation: deck.nation,
      deck: deck,
      headquarters_card: deck.headquarters_card
    )

    post waiting_heartbeat_game_path(game)

    assert_response :no_content

    game.reload
    assert_operator game.last_seen_at, :>, old_time
  end

  test "cannot send waiting heartbeat for another player's game" do
    owner = create_player
    player = create_player(email: "second@example.com")

    deck = create_complete_deck(player: owner)

    game = Game.create!(
      status: "waiting",
      last_seen_at: 1.minute.ago
    )

    game.game_players.create!(
      player: owner,
      nation: deck.nation,
      deck: deck,
      headquarters_card: deck.headquarters_card
    )

    post login_path, params: {
      email: player.email,
      password: "password"
    }

    old_time = game.last_seen_at

    post waiting_heartbeat_game_path(game)

    assert_response :forbidden

    game.reload
    assert_equal old_time.to_i, game.last_seen_at.to_i
  end

  test "cannot send waiting heartbeat for started game" do
    player = create_player
    deck = create_complete_deck(player: player)

    post login_path, params: {
      email: player.email,
      password: "password"
    }

    game = Game.create!(
      status: "started",
      state: {},
      last_seen_at: 1.minute.ago
    )

    game.game_players.create!(
      player: player,
      nation: deck.nation,
      deck: deck,
      headquarters_card: deck.headquarters_card
    )

    old_time = game.last_seen_at

    post waiting_heartbeat_game_path(game)

    assert_response :unprocessable_entity

    game.reload
    assert_equal old_time.to_i, game.last_seen_at.to_i
  end

  test "unauthenticated player cannot send waiting heartbeat" do
    player = create_player
    deck = create_complete_deck(player: player)

    game = Game.create!(
      status: "waiting",
      last_seen_at: 1.minute.ago
    )

    game.game_players.create!(
      player: player,
      nation: deck.nation,
      deck: deck,
      headquarters_card: deck.headquarters_card
    )

    old_time = game.last_seen_at

    post waiting_heartbeat_game_path(game)

    assert_response :unauthorized

    game.reload
    assert_equal old_time.to_i, game.last_seen_at.to_i
  end

  test "waiting game renders turbo stream subscription" do
    player = create_player
    deck = create_complete_deck(player: player)

    post login_path, params: {
      email: player.email,
      password: "password"
    }

    game = Game.create!(status: "waiting")

    game.game_players.create!(
      player: player,
      nation: deck.nation,
      deck: deck,
      headquarters_card: deck.headquarters_card
    )

    get game_path(game)

    assert_response :success
    assert_select "turbo-cable-stream-source"
  end

  test "waiting room shows weights of other waiting games" do
    player = create_player
    opponent = create_player(email: "opponent@example.com")
    another_opponent = create_player(email: "another@example.com")

    player_deck = create_complete_deck(player: player)
    opponent_deck = create_complete_deck(player: opponent)
    another_deck = create_complete_deck(player: another_opponent)

    game = Game.create!(status: "waiting")

    game.game_players.create!(
      player: player,
      nation: player_deck.nation,
      deck: player_deck,
      headquarters_card: player_deck.headquarters_card
    )

    opponent_game = Game.create!(status: "waiting")

    opponent_game.game_players.create!(
      player: opponent,
      nation: opponent_deck.nation,
      deck: opponent_deck,
      headquarters_card: opponent_deck.headquarters_card
    )

    another_game = Game.create!(status: "waiting")

    another_game.game_players.create!(
      player: another_opponent,
      nation: another_deck.nation,
      deck: another_deck,
      headquarters_card: another_deck.headquarters_card
    )

    post login_path, params: {
      email: player.email,
      password: "password"
    }

    get game_path(game)

    assert_response :success

    assert_select "li", minimum: 2
    assert_select "li", text: "Вес: #{opponent_deck.weight}"
    assert_select "li", text: "Вес: #{another_deck.weight}"
  end

  test "creating a waiting game refreshes other waiting rooms" do
    first_player = create_player
    second_player = create_player(email: "second@example.com")

    first_deck = create_complete_deck(player: first_player)
    second_deck = create_complete_deck(player: second_player)

    waiting_game = Game.create!(status: "waiting")

    waiting_game.game_players.create!(
      player: first_player,
      nation: first_deck.nation,
      deck: first_deck,
      headquarters_card: first_deck.headquarters_card
    )

    first_deck.deck_cards.first.card.update!(weight: 20)
    second_deck.deck_cards.first.card.update!(weight: 1)

    post login_path, params: {
      email: second_player.email,
      password: "password"
    }

    assert_difference("Game.count", 1) do
      post games_path, params: {
        deck_id: second_deck.id,
        mode: "pvp"
      }
    end

    created_game = Game
      .where(status: "waiting")
      .where.not(id: waiting_game.id)
      .order(:id)
      .last

    assert_not_nil created_game
    assert_redirected_to game_path(created_game)
    assert waiting_game.reload.waiting?
  end
  
	test "finishes game when player time expires through controller" do
		game = Game.create!
		player = create_player
		enemy = create_player

		nation = Nation.create!(
		  name: "Timeout Test Nation",
		  code: "timeout_test_nation"
		)

		enemy_nation = Nation.create!(
		  name: "Enemy Timeout Test Nation",
		  code: "enemy_timeout_test_nation"
		)

		headquarters_card = Card.create!(
		  nation: nation,
		  name: "Timeout Test HQ",
		  code: "timeout_test_hq_#{SecureRandom.hex(4)}",
		  card_type: "headquarters",
		  weight: 1,
		  price: nil
		)

		enemy_headquarters_card = Card.create!(
		  nation: enemy_nation,
		  name: "Enemy Timeout Test HQ",
		  code: "enemy_timeout_test_hq_#{SecureRandom.hex(4)}",
		  card_type: "headquarters",
		  weight: 1,
		  price: nil
		)

		deck = Deck.create!(
		  player: player,
		  nation: nation,
		  name: "Timeout Test Deck",
		  headquarters_card: headquarters_card
		)

		enemy_deck = Deck.create!(
		  player: enemy,
		  nation: enemy_nation,
		  name: "Enemy Timeout Enemy Deck",
		  headquarters_card: enemy_headquarters_card
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

		state = GameEngine::GameState.initial(
		  current_player_id: player.id,
		  participants: [
		    headquarters_participant(
		      player_id: player.id,
		      nation_id: nation.id
		    ),
		    headquarters_participant(
		      player_id: enemy.id,
		      nation_id: enemy_nation.id
		    )
		  ]
		)

		state["current_player_id"] = player.id.to_s
		state["turn_started_at"] = 10.minutes.ago.iso8601
		state["players"][player.id.to_s]["remaining_time"] = 1

		game.update!(state: state)

		log_in(player)

		post end_turn_path(game)

		assert_response :redirect

		game.reload

		assert game.finished?
		assert_equal "finished", game.state["status"]

		assert_equal(
		  {
		    "winner_id" => enemy.id.to_s,
		    "loser_id" => player.id.to_s,
		    "reason" => "time_expired"
		  },
		  game.state["result"]
		)

		player_actions = GameEngine::AvailableActions.call(
		  state: game.state,
		  player_id: player.id.to_s
		)

		enemy_actions = GameEngine::AvailableActions.call(
		  state: game.state,
		  player_id: enemy.id.to_s
		)

		assert_empty player_actions["field"]
		assert_empty player_actions["hand"]

		assert_empty enemy_actions["field"]
		assert_empty enemy_actions["hand"]

		finished_state = game.state.deep_dup

		post end_turn_path(game)

		assert_response :unprocessable_entity

		game.reload

		assert_equal finished_state, game.state
		assert game.finished?
		assert_equal "time_expired", game.state["result"]["reason"]
	end

test "finishes game when empty deck damage destroys headquarters through controller" do
  game = Game.create!
  player = create_player
  enemy = create_player

  nation = Nation.create!(
    name: "Empty Deck Test Nation",
    code: "empty_deck_test_nation"
  )

  enemy_nation = Nation.create!(
    name: "Enemy Empty Deck Test Nation",
    code: "enemy_empty_deck_test_nation"
  )

  headquarters_card = Card.create!(
    nation: nation,
    name: "Empty Deck Test HQ",
    code: "empty_deck_test_hq_#{SecureRandom.hex(4)}",
    card_type: "headquarters",
    weight: 1,
    price: nil
  )

  enemy_headquarters_card = Card.create!(
    nation: enemy_nation,
    name: "Enemy Empty Deck Test HQ",
    code: "enemy_empty_deck_test_hq_#{SecureRandom.hex(4)}",
    card_type: "headquarters",
    weight: 1,
    price: nil
  )

  deck = Deck.create!(
    player: player,
    nation: nation,
    name: "Empty Deck Test Deck",
    headquarters_card: headquarters_card
  )

  enemy_deck = Deck.create!(
    player: enemy,
    nation: enemy_nation,
    name: "Enemy Empty Deck Test Deck",
    headquarters_card: enemy_headquarters_card
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

  state = GameEngine::GameState.initial(
    current_player_id: player.id,
    participants: [
      headquarters_participant(
        player_id: player.id,
        nation_id: nation.id
      ),
      headquarters_participant(
        player_id: enemy.id,
        nation_id: enemy_nation.id
      )
    ]
  )

  state["current_player_id"] = player.id.to_s
  state["players"][enemy.id.to_s]["deck"] = []
  state["field"][0][4]["hp"] = 1

  game.update!(state: state)

  log_in(player)

  post end_turn_path(game)

  assert_response :redirect

  game.reload

  assert game.finished?
  assert_equal "finished", game.state["status"]

  assert_equal(
    {
      "winner_id" => player.id.to_s,
      "loser_id" => enemy.id.to_s,
      "reason" => "empty_deck_damage"
    },
    game.state["result"]
  )

  assert_equal 0, game.state["field"][0][4]["hp"]

  assert_equal(
    1,
    game.state["players"][enemy.id.to_s]["empty_deck_draw_attempts"]
  )

  player_actions = GameEngine::AvailableActions.call(
    state: game.state,
    player_id: player.id.to_s
  )

  enemy_actions = GameEngine::AvailableActions.call(
    state: game.state,
    player_id: enemy.id.to_s
  )

  assert_empty player_actions["field"]
  assert_empty player_actions["hand"]

  assert_empty enemy_actions["field"]
  assert_empty enemy_actions["hand"]

  finished_state = game.state.deep_dup

  post end_turn_path(game)

  assert_response :unprocessable_entity

  game.reload

  assert_equal finished_state, game.state
  assert game.finished?
  assert_equal "empty_deck_damage", game.state["result"]["reason"]
end

  private

  def find_object_coordinates(state, type, player_id)
    state["field"].each_with_index do |row, row_index|
      row.each_with_index do |cell, column_index|
        next unless cell
        next unless cell["type"] == type
        next unless cell["player_id"].to_s == player_id.to_s

        return [row_index, column_index]
      end
    end

    nil
  end
end
