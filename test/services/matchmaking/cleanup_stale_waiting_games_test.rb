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
  
  test "keeps finished games even when last_seen_at is stale" do
    game = Game.create!(
      status: "finished",
      state: {},
      last_seen_at: 31.seconds.ago
    )

    Matchmaking::CleanupStaleWaitingGames.call

    assert Game.exists?(game.id)
  end
  
  test "broadcasts refresh to remaining waiting games after stale game cleanup" do
    stale_player = create_player
    stale_deck = create_complete_deck(player: stale_player)

    stale_game = Game.create!(
      status: "waiting",
      last_seen_at: 31.seconds.ago
    )

    stale_game.game_players.create!(
      player: stale_player,
      nation: stale_deck.nation,
      deck: stale_deck,
      headquarters_card: stale_deck.headquarters_card
    )

    waiting_player = create_player(email: "waiting@example.com")
    waiting_deck = create_complete_deck(player: waiting_player)

    waiting_game = Game.create!(
      status: "waiting",
      last_seen_at: Time.current
    )

    waiting_game.game_players.create!(
      player: waiting_player,
      nation: waiting_deck.nation,
      deck: waiting_deck,
      headquarters_card: waiting_deck.headquarters_card
    )

    broadcasted_games = []

    original_method = Turbo::StreamsChannel.method(:broadcast_refresh_to)

    Turbo::StreamsChannel.define_singleton_method(:broadcast_refresh_to) do |game|
      broadcasted_games << game
    end

    begin
      Matchmaking::CleanupStaleWaitingGames.call
    ensure
      Turbo::StreamsChannel.define_singleton_method(
        :broadcast_refresh_to,
        original_method
      )
    end

    assert_not Game.exists?(stale_game.id)
    assert Game.exists?(waiting_game.id)
    assert_equal [waiting_game.id], broadcasted_games.map(&:id)
  end
end
