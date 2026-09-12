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

    GamePlayer.create!(
      game: game,
      player: player1,
      nation: nation1,
      deck: deck1
    )

    GamePlayer.create!(
      game: game,
      player: player2,
      nation: nation2,
      deck: deck2
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
        "player_id" => player1.id,
        "nation_id" => nation1.id
      },
      game.state["field"][2][0]
    )

    assert_equal(
      {
        "type" => "headquarters",
        "player_id" => player2.id,
        "nation_id" => nation2.id
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

    GamePlayer.create!(
      game: game,
      player: player,
      nation: nation,
      deck: deck
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

    GamePlayer.create!(
      game: game,
      player: player1,
      nation: nation1,
      deck: deck1
    )

    GamePlayer.create!(
      game: game,
      player: player2,
      nation: nation2,
      deck: deck2
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

    10.times do |index|
      card1 = Card.create!(
        nation: nation1,
        name: "Nation 1 Card #{index}",
        card_type: "order",
        weight: 1,
        price: 1
      )

      card2 = Card.create!(
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
      deck: deck1
    )

    GamePlayer.create!(
      game: game,
      player: player2,
      nation: nation2,
      deck: deck2
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

    10.times do |index|
      card1 = Card.create!(
        nation: nation1,
        name: "Nation 1 Card #{index}",
        card_type: "order",
        weight: 1,
        price: 1
      )

      card2 = Card.create!(
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
      deck: deck1
    )

    GamePlayer.create!(
      game: game,
      player: player2,
      nation: nation2,
      deck: deck2
    )

    assert_equal 10, deck1.card_count
    assert_equal 10, deck2.card_count

    GameEngine::StartGame.call(game)

    assert_equal 10, deck1.reload.card_count
    assert_equal 10, deck2.reload.card_count
    assert_equal 10, deck1.deck_cards.count
    assert_equal 10, deck2.deck_cards.count
  end
end
