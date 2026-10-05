require "test_helper"

module Matchmaking
  class FindOpponentTest < ActiveSupport::TestCase
    test "finds a compatible waiting game" do
      player = create_player
      opponent = create_player(email: "opponent@example.com")

      player_deck = create_complete_deck(player: player)
      opponent_deck = create_complete_deck(player: opponent)

      set_deck_weight(player_deck, 100)
      set_deck_weight(opponent_deck, 110)

      waiting_game = create_waiting_game(
        player: opponent,
        deck: opponent_deck
      )

      result = Matchmaking::FindOpponent.call(
        player: player,
        deck: player_deck
      )

      assert_equal waiting_game, result
    end

    test "does not find a game outside the weight allowance" do
      player = create_player
      opponent = create_player(email: "opponent@example.com")

      player_deck = create_complete_deck(player: player)
      opponent_deck = create_complete_deck(player: opponent)

      set_deck_weight(player_deck, 100)
      set_deck_weight(opponent_deck, 116)

      create_waiting_game(
        player: opponent,
        deck: opponent_deck
      )

      result = Matchmaking::FindOpponent.call(
        player: player,
        deck: player_deck
      )

      assert_nil result
    end

    test "does not find the player's own waiting game" do
      player = create_player
      deck = create_complete_deck(player: player)

      create_waiting_game(
        player: player,
        deck: deck
      )

      result = Matchmaking::FindOpponent.call(
        player: player,
        deck: deck
      )

      assert_nil result
    end

    test "chooses the smallest weight difference" do
      player = create_player

      first_opponent = create_player(email: "first@example.com")
      second_opponent = create_player(email: "second@example.com")

      player_deck = create_complete_deck(player: player)
      first_deck = create_complete_deck(player: first_opponent)
      second_deck = create_complete_deck(player: second_opponent)

      set_deck_weight(player_deck, 100)
      set_deck_weight(first_deck, 112)
      set_deck_weight(second_deck, 105)

      create_waiting_game(
        player: first_opponent,
        deck: first_deck
      )

      best_game = create_waiting_game(
        player: second_opponent,
        deck: second_deck
      )

      result = Matchmaking::FindOpponent.call(
        player: player,
        deck: player_deck
      )

      assert_equal best_game, result
    end

    test "chooses the oldest game when weight difference is equal" do
      player = create_player

      first_opponent = create_player(email: "first@example.com")
      second_opponent = create_player(email: "second@example.com")

      player_deck = create_complete_deck(player: player)
      first_deck = create_complete_deck(player: first_opponent)
      second_deck = create_complete_deck(player: second_opponent)

      set_deck_weight(player_deck, 100)
      set_deck_weight(first_deck, 110)
      set_deck_weight(second_deck, 90)

      oldest_game = create_waiting_game(
        player: first_opponent,
        deck: first_deck
      )

      sleep 0.01

      create_waiting_game(
        player: second_opponent,
        deck: second_deck
      )

      result = Matchmaking::FindOpponent.call(
        player: player,
        deck: player_deck
      )

      assert_equal oldest_game, result
    end

    private

    def set_deck_weight(deck, target_weight)
      card = deck.deck_cards.first.card

      current_weight = deck.weight
      card.update!(weight: card.weight + target_weight - current_weight)

      assert_equal target_weight, deck.reload.weight
    end

    def create_waiting_game(player:, deck:)
      game = Game.create!(status: "waiting")

      game.game_players.create!(
        player: player,
        nation: deck.nation,
        deck: deck,
        headquarters_card: deck.headquarters_card
      )

      game
    end
  end
end
