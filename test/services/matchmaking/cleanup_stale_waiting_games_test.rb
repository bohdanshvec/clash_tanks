require "test_helper"

class Matchmaking::CleanupStaleWaitingGamesTest < ActiveSupport::TestCase
  test "deletes stale waiting games" do
    player = create_player
    deck = create_complete_deck(player: player)

    game = Game.create!(
      status: "waiting",
      last_seen_at: 31.seconds.ago
    )

    game.game_players.create!(
      player: player,
      nation: deck.nation,
      deck: deck,
      headquarters_card: deck.headquarters_card
    )

    Matchmaking::CleanupStaleWaitingGames.call

    assert_not Game.exists?(game.id)
  end

  test "keeps fresh waiting games" do
    player = create_player
    deck = create_complete_deck(player: player)

    game = Game.create!(
      status: "waiting",
      last_seen_at: 10.seconds.ago
    )

    game.game_players.create!(
      player: player,
      nation: deck.nation,
      deck: deck,
      headquarters_card: deck.headquarters_card
    )

    Matchmaking::CleanupStaleWaitingGames.call

    assert Game.exists?(game.id)
  end

  test "keeps started games even when last_seen_at is stale" do
    player = create_player
    deck = create_complete_deck(player: player)

    game = Game.create!(
      status: "started",
      last_seen_at: 31.seconds.ago
    )

    game.game_players.create!(
      player: player,
      nation: deck.nation,
      deck: deck,
      headquarters_card: deck.headquarters_card
    )

    Matchmaking::CleanupStaleWaitingGames.call

    assert Game.exists?(game.id)
  end

  test "keeps waiting games with nil last_seen_at" do
    player = create_player
    deck = create_complete_deck(player: player)

    game = Game.create!(
      status: "waiting",
      last_seen_at: nil
    )

    game.game_players.create!(
      player: player,
      nation: deck.nation,
      deck: deck,
      headquarters_card: deck.headquarters_card
    )

    Matchmaking::CleanupStaleWaitingGames.call

    assert Game.exists?(game.id)
  end
end
