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

    game_player = GamePlayer.create!(
      game: game,
      player: player,
      nation: nation,
      deck: deck
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

    game_player = GamePlayer.create!(
      game: game,
      player: player,
      nation: nation,
      deck: deck
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

    game_player = GamePlayer.create!(
      game: game,
      player: player,
      nation: nation,
      deck: deck
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

    game_player = GamePlayer.create!(
      game: game,
      player: player,
      nation: nation,
      deck: deck
    )

    assert_equal deck, game_player.deck
  end
end
