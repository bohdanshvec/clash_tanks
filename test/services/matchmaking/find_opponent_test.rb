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
    
		test "finds a game at the exact upper compatibility boundary" do
			player = create_player
			opponent = create_player(email: "opponent@example.com")

			player_deck = create_complete_deck(player: player)
			opponent_deck = create_complete_deck(player: opponent)

			set_deck_weight(player_deck, 100)
			set_deck_weight(opponent_deck, 115)

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

		test "finds a game at the exact lower compatibility boundary" do
			player = create_player
			opponent = create_player(email: "opponent@example.com")

			player_deck = create_complete_deck(player: player)
			opponent_deck = create_complete_deck(player: opponent)

			set_deck_weight(player_deck, 100)
			set_deck_weight(opponent_deck, 87)

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

		test "does not find a game just outside the lower compatibility boundary" do
			player = create_player
			opponent = create_player(email: "opponent@example.com")

			player_deck = create_complete_deck(player: player)
			opponent_deck = create_complete_deck(player: opponent)

			set_deck_weight(player_deck, 100)
			set_deck_weight(opponent_deck, 86)

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

		test "ignores started and finished games" do
			player = create_player
			started_player = create_player(email: "started@example.com")
			finished_player = create_player(email: "finished@example.com")

			player_deck = create_complete_deck(player: player)
			started_deck = create_complete_deck(player: started_player)
			finished_deck = create_complete_deck(player: finished_player)

			set_deck_weight(player_deck, 100)
			set_deck_weight(started_deck, 100)
			set_deck_weight(finished_deck, 100)

			started_game = Game.create!(
				status: "started",
				state: {}
			)

			started_game.game_players.create!(
				player: started_player,
				nation: started_deck.nation,
				deck: started_deck,
				headquarters_card: started_deck.headquarters_card
			)

			finished_game = Game.create!(
				status: "finished",
				state: {}
			)

			finished_game.game_players.create!(
				player: finished_player,
				nation: finished_deck.nation,
				deck: finished_deck,
				headquarters_card: finished_deck.headquarters_card
			)

			result = Matchmaking::FindOpponent.call(
				player: player,
				deck: player_deck
			)

			assert_nil result
		end

		test "ignores a waiting game that already has two players" do
			player = create_player
			first_opponent = create_player(email: "first@example.com")
			second_opponent = create_player(email: "second@example.com")

			player_deck = create_complete_deck(player: player)
			first_deck = create_complete_deck(player: first_opponent)
			second_deck = create_complete_deck(player: second_opponent)

			set_deck_weight(player_deck, 100)
			set_deck_weight(first_deck, 100)
			set_deck_weight(second_deck, 100)

			waiting_game = Game.create!(status: "waiting")

			waiting_game.game_players.create!(
				player: first_opponent,
				nation: first_deck.nation,
				deck: first_deck,
				headquarters_card: first_deck.headquarters_card
			)

			waiting_game.game_players.create!(
				player: second_opponent,
				nation: second_deck.nation,
				deck: second_deck,
				headquarters_card: second_deck.headquarters_card
			)

			result = Matchmaking::FindOpponent.call(
				player: player,
				deck: player_deck
			)

			assert_nil result
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
