require "test_helper"

class GamePlayerTest < ActiveSupport::TestCase
  test "belongs to game" do
    game = Game.create!
    player = Player.create!
    nation = Nation.create!(
      name: "СССР",
      code: "ussr"
    )
    deck = Deck.create!(
      player: player,
      nation: nation,
      name: "Основная колода"
    )
    headquarters_card = create_headquarters_card(nation: nation)

    game_player = GamePlayer.create!(
      game: game,
      player: player,
      nation: nation,
      deck: deck,
      headquarters_card: headquarters_card
    )

    assert_equal game, game_player.game
  end

  test "belongs to player" do
    game = Game.create!
    player = Player.create!
    nation = Nation.create!(
      name: "СССР",
      code: "ussr"
    )
    deck = Deck.create!(
      player: player,
      nation: nation,
      name: "Основная колода"
    )
    headquarters_card = create_headquarters_card(nation: nation)

    game_player = GamePlayer.create!(
      game: game,
      player: player,
      nation: nation,
      deck: deck,
      headquarters_card: headquarters_card
    )

    assert_equal player, game_player.player
  end

  test "belongs to nation" do
    game = Game.create!
    player = Player.create!
    nation = Nation.create!(
      name: "СССР",
      code: "ussr"
    )
    deck = Deck.create!(
      player: player,
      nation: nation,
      name: "Основная колода"
    )
    headquarters_card = create_headquarters_card(nation: nation)

    game_player = GamePlayer.create!(
      game: game,
      player: player,
      nation: nation,
      deck: deck,
      headquarters_card: headquarters_card
    )

    assert_equal nation, game_player.nation
  end

  test "belongs to deck" do
    game = Game.create!
    player = Player.create!
    nation = Nation.create!(
      name: "СССР",
      code: "ussr"
    )
    deck = Deck.create!(
      player: player,
      nation: nation,
      name: "Основная колода"
    )
    headquarters_card = create_headquarters_card(nation: nation)

    game_player = GamePlayer.create!(
      game: game,
      player: player,
      nation: nation,
      deck: deck,
      headquarters_card: headquarters_card
    )

    assert_equal deck, game_player.deck
  end

  private

  def create_headquarters_card(nation:)
    card = Card.create!(
      code: "test_hq",
      nation: nation,
      name: "Test HQ",
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
