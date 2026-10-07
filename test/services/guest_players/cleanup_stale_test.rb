require "test_helper"

class GuestPlayers::CleanupStaleTest < ActiveSupport::TestCase

	setup do
    Rails.application.load_seed
  end
  
  test "deletes stale guest without games" do
    guest = GuestPlayers::Create.call
    guest.update!(last_seen_at: 25.hours.ago)

    assert_difference("Player.count", -1) do
      GuestPlayers::CleanupStale.call
    end

    assert_not Player.exists?(guest.id)
  end

  test "deletes stale guest and its decks" do
    guest = GuestPlayers::Create.call
    guest.update!(last_seen_at: 25.hours.ago)

    assert_difference("Deck.count", -3) do
      GuestPlayers::CleanupStale.call
    end

    assert_not Player.exists?(guest.id)
  end

  test "deletes stale guest with finished game" do
    guest = GuestPlayers::Create.call
    guest.update!(last_seen_at: 25.hours.ago)

    deck = guest.decks.first

    game = Game.create!(
      status: "finished",
      state: {},
      last_seen_at: 25.hours.ago
    )

    game_player = game.game_players.create!(
      player: guest,
      nation: deck.nation,
      deck: deck,
      headquarters_card: deck.headquarters_card
    )

    GuestPlayers::CleanupStale.call

    assert_not Player.exists?(guest.id)
    assert Game.exists?(game.id)
    assert_not GamePlayer.exists?(game_player.id)
  end

  test "keeps stale guest with waiting game" do
    guest = GuestPlayers::Create.call
    guest.update!(last_seen_at: 25.hours.ago)

    deck = guest.decks.first

    game = Game.create!(
      status: "waiting",
      last_seen_at: 25.hours.ago
    )

    game.game_players.create!(
      player: guest,
      nation: deck.nation,
      deck: deck,
      headquarters_card: deck.headquarters_card
    )

    GuestPlayers::CleanupStale.call

    assert Player.exists?(guest.id)
    assert Game.exists?(game.id)
  end

  test "keeps stale guest with started game" do
    guest = GuestPlayers::Create.call
    guest.update!(last_seen_at: 25.hours.ago)

    deck = guest.decks.first

    game = Game.create!(
      status: "started",
      state: {},
      last_seen_at: 25.hours.ago
    )

    game.game_players.create!(
      player: guest,
      nation: deck.nation,
      deck: deck,
      headquarters_card: deck.headquarters_card
    )

    GuestPlayers::CleanupStale.call

    assert Player.exists?(guest.id)
    assert Game.exists?(game.id)
  end

  test "keeps fresh guest" do
    guest = GuestPlayers::Create.call
    guest.update!(last_seen_at: 23.hours.ago)

    GuestPlayers::CleanupStale.call

    assert Player.exists?(guest.id)
    assert_equal 3, guest.reload.decks.count
  end

  test "keeps guest with nil last_seen_at" do
    guest = GuestPlayers::Create.call
    guest.update!(last_seen_at: nil)

    GuestPlayers::CleanupStale.call

    assert Player.exists?(guest.id)
  end

  test "does not delete registered players" do
    player = create_player
    player.update!(last_seen_at: 25.hours.ago)

    GuestPlayers::CleanupStale.call

    assert Player.exists?(player.id)
  end
end
