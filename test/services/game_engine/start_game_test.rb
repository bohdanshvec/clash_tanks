require "test_helper"

class GameEngine::StartGameTest < ActiveSupport::TestCase
  test "starts a waiting game with two players" do
    game = Game.create!
    player1 = Player.create!
    player2 = Player.create!

    nation1 = Nation.create!(
      name: "Nation 1",
      code: "nation_1"
    )

    nation2 = Nation.create!(
      name: "Nation 2",
      code: "nation_2"
    )

    deck1 = Deck.create!(
      player: player1,
      nation: nation1,
      name: "Deck 1"
    )

    deck2 = Deck.create!(
      player: player2,
      nation: nation2,
      name: "Deck 2"
    )

    headquarters1 = create_headquarters_card(nation: nation1, name: "HQ 1")
    headquarters2 = create_headquarters_card(nation: nation2, name: "HQ 2")

    GamePlayer.create!(
      game: game,
      player: player1,
      nation: nation1,
      deck: deck1,
      headquarters_card: headquarters1
    )

    GamePlayer.create!(
      game: game,
      player: player2,
      nation: nation2,
      deck: deck2,
      headquarters_card: headquarters2
    )

    GameEngine::StartGame.call(game)

    game.reload

    assert game.started?
    assert_equal 1, game.state["turn_number"]
    assert_includes [player1.id, player2.id], game.state["current_player_id"]

    assert_equal(
      [player1.id.to_s, player2.id.to_s].sort,
      game.state["players"].keys.sort
    )

    assert_equal(
      nation1.id,
      game.state["players"][player1.id.to_s]["nation_id"]
    )

    assert_equal(
      nation2.id,
      game.state["players"][player2.id.to_s]["nation_id"]
    )

    assert_equal(
      {
        "type" => "headquarters",
        "card_id" => headquarters1.id,
        "player_id" => player1.id,
        "nation_id" => nation1.id,
        "name" => "HQ 1",
        "hp" => 20,
        "firepower" => 3,
        "fuel" => 5,
        "has_attacked" => false,
        "has_counterattacked" => false,
        "abilities" => []
      },
      game.state["field"][2][0]
    )

    assert_equal(
      {
        "type" => "headquarters",
        "card_id" => headquarters2.id,
        "player_id" => player2.id,
        "nation_id" => nation2.id,
        "name" => "HQ 2",
        "hp" => 20,
        "firepower" => 3,
        "fuel" => 5,
        "has_attacked" => false,
        "has_counterattacked" => false,
        "abilities" => []
      },
      game.state["field"][0][4]
    )
  end

  test "does not start a game with one player" do
    game = Game.create!
    player = Player.create!

    nation = Nation.create!(
      name: "Nation 1",
      code: "nation_1"
    )

    deck = Deck.create!(
      player: player,
      nation: nation,
      name: "Deck 1"
    )

    headquarters = create_headquarters_card(nation: nation)

    GamePlayer.create!(
      game: game,
      player: player,
      nation: nation,
      deck: deck,
      headquarters_card: headquarters
    )

    assert_raises(ArgumentError, "Game must have exactly two players") do
      GameEngine::StartGame.call(game)
    end

    game.reload

    assert game.waiting?
    assert_nil game.state
  end

  test "does not start a game that has already started" do
    game = Game.create!
    player1 = Player.create!
    player2 = Player.create!

    nation1 = Nation.create!(
      name: "Nation 1",
      code: "nation_1"
    )

    nation2 = Nation.create!(
      name: "Nation 2",
      code: "nation_2"
    )

    deck1 = Deck.create!(
      player: player1,
      nation: nation1,
      name: "Deck 1"
    )

    deck2 = Deck.create!(
      player: player2,
      nation: nation2,
      name: "Deck 2"
    )

    headquarters1 = create_headquarters_card(nation: nation1)
    headquarters2 = create_headquarters_card(nation: nation2)

    GamePlayer.create!(
      game: game,
      player: player1,
      nation: nation1,
      deck: deck1,
      headquarters_card: headquarters1
    )

    GamePlayer.create!(
      game: game,
      player: player2,
      nation: nation2,
      deck: deck2,
      headquarters_card: headquarters2
    )

    GameEngine::StartGame.call(game)

    assert_raises(ArgumentError, "Game must be waiting") do
      GameEngine::StartGame.call(game)
    end
  end

  test "starts a game with six cards in hand and remaining cards in deck" do
    game = Game.create!

    player1 = Player.create!
    player2 = Player.create!

    nation1 = Nation.create!(
      name: "Nation 1",
      code: "nation_1"
    )

    nation2 = Nation.create!(
      name: "Nation 2",
      code: "nation_2"
    )

    deck1 = Deck.create!(
      player: player1,
      nation: nation1,
      name: "Deck 1"
    )

    deck2 = Deck.create!(
      player: player2,
      nation: nation2,
      name: "Deck 2"
    )

    headquarters1 = create_headquarters_card(nation: nation1)
    headquarters2 = create_headquarters_card(nation: nation2)

    10.times do |index|
      card1 = Card.create!(
        code: "nation_1_card_#{index}",
        nation: nation1,
        name: "Nation 1 Card #{index}",
        card_type: "order",
        weight: 1,
        price: 1
      )

      card2 = Card.create!(
        code: "nation_2_card_#{index}",
        nation: nation2,
        name: "Nation 2 Card #{index}",
        card_type: "order",
        weight: 1,
        price: 1
      )

      DeckCard.create!(
        deck: deck1,
        card: card1,
        quantity: 1
      )

      DeckCard.create!(
        deck: deck2,
        card: card2,
        quantity: 1
      )
    end

    GamePlayer.create!(
      game: game,
      player: player1,
      nation: nation1,
      deck: deck1,
      headquarters_card: headquarters1
    )

    GamePlayer.create!(
      game: game,
      player: player2,
      nation: nation2,
      deck: deck2,
      headquarters_card: headquarters2
    )

    GameEngine::StartGame.call(game)

    game.reload

    player1_state = game.state["players"][player1.id.to_s]
    player2_state = game.state["players"][player2.id.to_s]

    assert_equal 6, player1_state["hand"].size
    assert_equal 4, player1_state["deck"].size

    assert_equal 6, player2_state["hand"].size
    assert_equal 4, player2_state["deck"].size

    assert_equal 10, player1_state["hand"].size + player1_state["deck"].size
    assert_equal 10, player2_state["hand"].size + player2_state["deck"].size
    refute_includes player1_state["hand"] + player1_state["deck"], headquarters1.id
    refute_includes player2_state["hand"] + player2_state["deck"], headquarters2.id
  end

  test "does not modify saved decks when starting a game" do
    game = Game.create!

    player1 = Player.create!
    player2 = Player.create!

    nation1 = Nation.create!(
      name: "Nation 1",
      code: "nation_1"
    )

    nation2 = Nation.create!(
      name: "Nation 2",
      code: "nation_2"
    )

    deck1 = Deck.create!(
      player: player1,
      nation: nation1,
      name: "Deck 1"
    )

    deck2 = Deck.create!(
      player: player2,
      nation: nation2,
      name: "Deck 2"
    )

    headquarters1 = create_headquarters_card(nation: nation1)
    headquarters2 = create_headquarters_card(nation: nation2)

    10.times do |index|
      card1 = Card.create!(
        code: "nation_1_card_#{index}",
        nation: nation1,
        name: "Nation 1 Card #{index}",
        card_type: "order",
        weight: 1,
        price: 1
      )

      card2 = Card.create!(
        code: "nation_2_card_#{index}",
        nation: nation2,
        name: "Nation 2 Card #{index}",
        card_type: "order",
        weight: 1,
        price: 1
      )

      DeckCard.create!(
        deck: deck1,
        card: card1,
        quantity: 1
      )

      DeckCard.create!(
        deck: deck2,
        card: card2,
        quantity: 1
      )
    end

    GamePlayer.create!(
      game: game,
      player: player1,
      nation: nation1,
      deck: deck1,
      headquarters_card: headquarters1
    )

    GamePlayer.create!(
      game: game,
      player: player2,
      nation: nation2,
      deck: deck2,
      headquarters_card: headquarters2
    )

    assert_equal 10, deck1.card_count
    assert_equal 10, deck2.card_count

    GameEngine::StartGame.call(game)

    assert_equal 10, deck1.reload.card_count
    assert_equal 10, deck2.reload.card_count
    assert_equal 10, deck1.deck_cards.count
    assert_equal 10, deck2.deck_cards.count
  end

  test "serializes headquarters abilities without ability names" do
    game = Game.create!
    player1 = Player.create!
    player2 = Player.create!
    nation1 = Nation.create!(name: "Nation 1", code: "nation_1")
    nation2 = Nation.create!(name: "Nation 2", code: "nation_2")
    deck1 = Deck.create!(player: player1, nation: nation1, name: "Deck 1")
    deck2 = Deck.create!(player: player2, nation: nation2, name: "Deck 2")
    headquarters1 = create_headquarters_card(nation: nation1)
    headquarters2 = create_headquarters_card(nation: nation2)
    ability = Ability.create!(name: "Test ability", code: "test_headquarters_ability")

    CardAbility.create!(
      card: headquarters1,
      ability: ability,
      parameters: { "bonus" => 2 }
    )

    GamePlayer.create!(
      game: game,
      player: player1,
      nation: nation1,
      deck: deck1,
      headquarters_card: headquarters1
    )

    GamePlayer.create!(
      game: game,
      player: player2,
      nation: nation2,
      deck: deck2,
      headquarters_card: headquarters2
    )

    GameEngine::StartGame.call(game)

    assert_equal [
      { "code" => "test_headquarters_ability", "bonus" => 2 }
    ], game.reload.state["field"][2][0]["abilities"]
  end

  test "calculates fuel for the first player's turn" do
    game = Game.create!

    player1 = Player.create!
    player2 = Player.create!

    nation1 = Nation.create!(
      name: "Nation 1",
      code: "nation_1"
    )

    nation2 = Nation.create!(
      name: "Nation 2",
      code: "nation_2"
    )

    deck1 = Deck.create!(
      player: player1,
      nation: nation1,
      name: "Deck 1"
    )

    deck2 = Deck.create!(
      player: player2,
      nation: nation2,
      name: "Deck 2"
    )

    headquarters1 = create_headquarters_card(
      nation: nation1,
      name: "HQ 1"
    )

    headquarters2 = create_headquarters_card(
      nation: nation2,
      name: "HQ 2"
    )

    GamePlayer.create!(
      game: game,
      player: player1,
      nation: nation1,
      deck: deck1,
      headquarters_card: headquarters1
    )

    GamePlayer.create!(
      game: game,
      player: player2,
      nation: nation2,
      deck: deck2,
      headquarters_card: headquarters2
    )

    GameEngine::StartGame.call(game)

    game.reload

    current_player_id = game.state["current_player_id"]

    opponent_id = [player1.id, player2.id].find do |player_id|
      player_id != current_player_id
    end

    assert_equal 5, game.state["players"][current_player_id.to_s]["resources"]
    assert_equal 0, game.state["players"][opponent_id.to_s]["resources"]
  end

  test "initializes empty deck draw attempt counter" do
    game = Game.create!

    player1 = Player.create!
    player2 = Player.create!

    nation1 = Nation.create!(
      name: "Nation 1",
      code: "nation_1"
    )

    nation2 = Nation.create!(
      name: "Nation 2",
      code: "nation_2"
    )

    deck1 = Deck.create!(
      player: player1,
      nation: nation1,
      name: "Deck 1"
    )

    deck2 = Deck.create!(
      player: player2,
      nation: nation2,
      name: "Deck 2"
    )

    headquarters1 = create_headquarters_card(nation: nation1)
    headquarters2 = create_headquarters_card(nation: nation2)

    GamePlayer.create!(
      game: game,
      player: player1,
      nation: nation1,
      deck: deck1,
      headquarters_card: headquarters1
    )

    GamePlayer.create!(
      game: game,
      player: player2,
      nation: nation2,
      deck: deck2,
      headquarters_card: headquarters2
    )

    GameEngine::StartGame.call(game)

    game.reload

    assert_equal(
      0,
      game.state["players"][player1.id.to_s]["empty_deck_draw_attempts"]
    )

    assert_equal(
      0,
      game.state["players"][player2.id.to_s]["empty_deck_draw_attempts"]
    )
  end

  test "does not draw an extra card at game start" do
    game = Game.create!

    player1 = Player.create!
    player2 = Player.create!

    nation1 = Nation.create!(
      name: "Nation 1",
      code: "nation_1"
    )

    nation2 = Nation.create!(
      name: "Nation 2",
      code: "nation_2"
    )

    deck1 = Deck.create!(
      player: player1,
      nation: nation1,
      name: "Deck 1"
    )

    deck2 = Deck.create!(
      player: player2,
      nation: nation2,
      name: "Deck 2"
    )

    headquarters1 = create_headquarters_card(nation: nation1)
    headquarters2 = create_headquarters_card(nation: nation2)

    10.times do |index|
      card1 = Card.create!(
        code: "nation_1_card_#{index}",
        nation: nation1,
        name: "Nation 1 Card #{index}",
        card_type: "order",
        weight: 1,
        price: 1
      )

      card2 = Card.create!(
        code: "nation_2_card_#{index}",
        nation: nation2,
        name: "Nation 2 Card #{index}",
        card_type: "order",
        weight: 1,
        price: 1
      )

      DeckCard.create!(
        deck: deck1,
        card: card1,
        quantity: 1
      )

      DeckCard.create!(
        deck: deck2,
        card: card2,
        quantity: 1
      )
    end

    GamePlayer.create!(
      game: game,
      player: player1,
      nation: nation1,
      deck: deck1,
      headquarters_card: headquarters1
    )

    GamePlayer.create!(
      game: game,
      player: player2,
      nation: nation2,
      deck: deck2,
      headquarters_card: headquarters2
    )

    GameEngine::StartGame.call(game)

    game.reload

    player1_state = game.state["players"][player1.id.to_s]
    player2_state = game.state["players"][player2.id.to_s]

    assert_equal 6, player1_state["hand"].size
    assert_equal 4, player1_state["deck"].size

    assert_equal 6, player2_state["hand"].size
    assert_equal 4, player2_state["deck"].size
  end

  private

  def create_headquarters_card(nation:, name: "Test HQ")
    card = Card.create!(
      code: "#{nation.code}_#{name.parameterize(separator: "_")}",
      nation: nation,
      name: name,
      card_type: "headquarters",
      weight: 1,
      price: nil
    )

    Headquarters.create!(
      card: card,
      hp: 20,
      firepower: 3,
      fuel: 5
    )

    card
  end
end
