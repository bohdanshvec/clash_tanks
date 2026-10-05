require "test_helper"

module Matchmaking
  class JoinTest < ActiveSupport::TestCase
    test "joins a player to a waiting game and starts it" do
      first_player = create_player
      second_player = create_player(email: "second@example.com")

      first_deck = create_complete_deck(player: first_player)
      second_deck = create_complete_deck(player: second_player)

      game = Game.create!(status: "waiting")

      game.game_players.create!(
        player: first_player,
        nation: first_deck.nation,
        deck: first_deck,
        headquarters_card: first_deck.headquarters_card
      )

      result = Matchmaking::Join.call(
        game: game,
        player: second_player,
        deck: second_deck
      )

      assert_equal game, result

      game.reload

      assert game.started?
      assert_not_nil game.state
      assert_equal 2, game.game_players.count
      assert_includes game.players, first_player
      assert_includes game.players, second_player
    end

    test "does not join a game that is already started" do
      first_player = create_player
      second_player = create_player(email: "second@example.com")

      first_deck = create_complete_deck(player: first_player)
      second_deck = create_complete_deck(player: second_player)

      game = Game.create!(
        status: "started",
        state: {}
      )

      game.game_players.create!(
        player: first_player,
        nation: first_deck.nation,
        deck: first_deck,
        headquarters_card: first_deck.headquarters_card
      )

      result = Matchmaking::Join.call(
        game: game,
        player: second_player,
        deck: second_deck
      )

      assert_nil result

      game.reload

      assert game.started?
      assert_equal 1, game.game_players.count
    end

    test "does not join a game that already has two players" do
      first_player = create_player
      second_player = create_player(email: "second@example.com")
      third_player = create_player(email: "third@example.com")

      first_deck = create_complete_deck(player: first_player)
      second_deck = create_complete_deck(player: second_player)
      third_deck = create_complete_deck(player: third_player)

      game = Game.create!(status: "waiting")

      game.game_players.create!(
        player: first_player,
        nation: first_deck.nation,
        deck: first_deck,
        headquarters_card: first_deck.headquarters_card
      )

      game.game_players.create!(
        player: second_player,
        nation: second_deck.nation,
        deck: second_deck,
        headquarters_card: second_deck.headquarters_card
      )

      result = Matchmaking::Join.call(
        game: game,
        player: third_player,
        deck: third_deck
      )

      assert_nil result

      game.reload

      assert_equal 2, game.game_players.count
      assert game.waiting?
    end

    test "does not add the same player twice" do
      player = create_player
      deck = create_complete_deck(player: player)

      game = Game.create!(status: "waiting")

      game.game_players.create!(
        player: player,
        nation: deck.nation,
        deck: deck,
        headquarters_card: deck.headquarters_card
      )

      result = Matchmaking::Join.call(
        game: game,
        player: player,
        deck: deck
      )

      assert_nil result

      game.reload

      assert_equal 1, game.game_players.count
      assert game.waiting?
    end
  end
end
