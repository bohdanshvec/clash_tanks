require "test_helper"

class DecksControllerTest < ActionDispatch::IntegrationTest
	setup do
		Rails.application.load_seed
		@player = create_player(email: "player@example.com")
		StarterDecks::Create.call(@player)
		@deck = @player.decks.first
	end

	test "guest is redirected from new deck" do
		get new_deck_path

		assert_redirected_to login_path
	end

	test "guest is redirected from edit deck" do
		get edit_deck_path(@deck)

		assert_redirected_to login_path
	end

	test "logged in player can access new deck" do
		post login_path, params: {
			email: @player.email,
			password: "password"
		}

		get new_deck_path

		assert_response :success
	end

	test "logged in player can access edit their own deck" do
		post login_path, params: {
			email: @player.email,
			password: "password"
		}

		get edit_deck_path(@deck)

		assert_response :success
	end

	test "logged in player cannot edit another player's deck" do
		other_player = create_player(email: "other@example.com")
		StarterDecks::Create.call(other_player)
		other_deck = other_player.decks.first

		post login_path, params: {
			email: @player.email,
			password: "password"
		}

		get edit_deck_path(other_deck)

		assert_response :not_found
	end
	
	test "logged in player can create a deck" do
		post login_path, params: {
			email: @player.email,
			password: "password"
		}

		headquarters_card = Card.find_by!(
			code: "germany_headquarters_operation_weiß"
			)

		card = Card
		.where(nation_id: headquarters_card.nation_id)
		.where.not(card_type: "headquarters")
		.first!

		assert_difference("Deck.count", 1) do
			post decks_path, params: {
				deck: {
					name: "Моя колода",
					headquarters_card_id: headquarters_card.id,
					card_quantities: {
						card.id => 1
					}
				}
			}
		end

		assert_redirected_to decks_path

		deck = @player.decks.find_by!(name: "Моя колода")

		assert_equal headquarters_card.id, deck.headquarters_card_id
		assert_equal headquarters_card.nation_id, deck.nation_id
		assert_equal 1, deck.card_count
	end

	test "logged in player cannot create an empty deck" do
		post login_path, params: {
			email: @player.email,
			password: "password"
		}

		headquarters_card = @deck.headquarters_card

		assert_no_difference("Deck.count") do
			post decks_path, params: {
				deck: {
					name: "Порожня колода",
					headquarters_card_id: headquarters_card.id,
					card_quantities: {}
				}
			}
		end

		assert_response :unprocessable_entity
		assert_includes response.body,
		"Колода повинна містити щонайменше 1 карту"
	end

	test "logged in player cannot remove all cards from their deck" do
		post login_path, params: {
			email: @player.email,
			password: "password"
		}

		original_count = @deck.card_count
		original_name = @deck.name

		patch deck_path(@deck), params: {
			deck: {
				name: "Порожня колода",
				card_quantities: {}
			}
		}

		assert_response :unprocessable_entity

		@deck.reload

		assert_equal original_count, @deck.card_count
		assert_equal original_name, @deck.name
	end

	test "logged in player can update their deck" do
		post login_path, params: {
			email: @player.email,
			password: "password"
		}

		headquarters_card = @deck.headquarters_card
		card = Card.where(
			nation_id: headquarters_card.nation_id
			).where.not(card_type: "headquarters").first

		patch deck_path(@deck), params: {
			deck: {
				name: "Изменённая колода",
				card_quantities: {
					card.id => 2
				}
			}
		}

		assert_redirected_to decks_path

		@deck.reload

		assert_equal "Изменённая колода", @deck.name
		assert_equal headquarters_card.id, @deck.headquarters_card_id
		assert_equal headquarters_card.nation_id, @deck.nation_id
		assert_equal 2, @deck.card_count
		assert_equal 2, @deck.deck_cards.find_by(card: card).quantity
	end

	test "logged in player cannot create a deck with cards from another nation" do
		post login_path, params: {
			email: @player.email,
			password: "password"
		}

		germany_hq = Card.find_by!(
			code: "germany_headquarters_operation_weiß"
			)

		usa_card = Card
		.where(nation: Nation.find_by!(code: "usa"))
		.where.not(card_type: "headquarters")
		.first

		assert_no_difference("Deck.count") do
			post decks_path, params: {
				deck: {
					name: "Неверная колода",
					headquarters_card_id: germany_hq.id,
					card_quantities: {
						usa_card.id => 1
					}
				}
			}
		end

		assert_response :unprocessable_entity
	end

	test "logged in player cannot exceed three copies of a card" do
		post login_path, params: {
			email: @player.email,
			password: "password"
		}

		headquarters_card = @deck.headquarters_card

		card = Card.where(
			nation_id: headquarters_card.nation_id
			).where.not(card_type: "headquarters").first

		assert_no_difference("Deck.count") do
			post decks_path, params: {
				deck: {
					name: "Неверная колода",
					headquarters_card_id: headquarters_card.id,
					card_quantities: {
						card.id => 4
					}
				}
			}
		end

		assert_response :unprocessable_entity
	end
	
	test "logged in player cannot create a deck with more than fifteen cards" do
		post login_path, params: {
			email: @player.email,
			password: "password"
		}

		headquarters_card = @deck.headquarters_card

		cards = Card
		.where(nation_id: headquarters_card.nation_id)
		.where.not(card_type: "headquarters")
		.limit(6)

		card_quantities = cards.index_with { 3 }

		assert_equal 18, card_quantities.values.sum

		assert_no_difference("Deck.count") do
			post decks_path, params: {
				deck: {
					name: "Слишком большая колода",
					headquarters_card_id: headquarters_card.id,
					card_quantities: card_quantities
				}
			}
		end

		assert_response :unprocessable_entity
	end

	test "destroying deck cancels its waiting PvP game" do
	  post login_path, params: {
	    email: @player.email,
	    password: "password"
	  }

	  game = Game.create!(
	    mode: "pvp",
	    status: "waiting"
	  )

	  game_player = game.game_players.create!(
	    player: @player,
	    nation: @deck.nation,
	    deck: @deck,
	    headquarters_card: @deck.headquarters_card
	  )

	  assert_difference("Deck.count", -1) do
	    assert_difference("Game.count", -1) do
	      assert_difference("GamePlayer.count", -1) do
	        delete deck_path(@deck)
	      end
	    end
	  end

	  assert_redirected_to decks_path

	  assert_not Deck.exists?(@deck.id)
	  assert_not Game.exists?(game.id)
	  assert_not GamePlayer.exists?(game_player.id)
	end

	test "destroying deck surrenders in started PvP game" do
	  opponent = create_player(email: "opponent@example.com")
	  opponent_deck = create_complete_deck(player: opponent)

	  game = create_started_pvp_game(
	    first_player: @player,
	    first_deck: @deck,
	    second_player: opponent,
	    second_deck: opponent_deck
	  )

	  player_game_record = game.game_players.find_by!(player: @player)
	  opponent_game_record = game.game_players.find_by!(player: opponent)

	  player_statistics_before = player_statistics(@player)
	  opponent_statistics_before = player_statistics(opponent)

	  post login_path, params: {
	    email: @player.email,
	    password: "password"
	  }

	  assert_difference("Deck.count", -1) do
	    delete deck_path(@deck)
	  end

	  assert_redirected_to decks_path

	  game.reload

	  assert Game.exists?(game.id)
	  assert game.finished?

	  result = game.state.fetch("result")

	  assert_equal "surrender", result.fetch("reason")
		assert_equal opponent.id, result.fetch("winner_id").to_i
		assert_equal @player.id, result.fetch("loser_id").to_i

	  assert_nil player_game_record.reload.deck_id
	  assert_equal opponent_deck.id, opponent_game_record.reload.deck_id

	  assert_equal(
	    player_statistics_before.merge(
	      "battles_count" => player_statistics_before["battles_count"] + 1,
	      "losses_count" => player_statistics_before["losses_count"] + 1
	    ),
	    player_statistics(@player)
	  )

	  assert_equal(
	    opponent_statistics_before.merge(
	      "battles_count" => opponent_statistics_before["battles_count"] + 1,
	      "wins_count" => opponent_statistics_before["wins_count"] + 1
	    ),
	    player_statistics(opponent)
	  )
	end

	test "destroying deck preserves finished PvP game history and statistics" do
	  opponent = create_player(email: "opponent@example.com")
	  opponent_deck = create_complete_deck(player: opponent)

	  game = create_started_pvp_game(
	    first_player: @player,
	    first_deck: @deck,
	    second_player: opponent,
	    second_deck: opponent_deck
	  )

	  # Противник сдаётся, чтобы завершить партию
	  # через настоящий GameActionRunner.
	  surrender_game!(
	    game: game,
	    player: opponent
	  )

	  game.reload

	  original_result = game.state.fetch("result").deep_dup
	  original_statistics = {
	    player: player_statistics(@player),
	    opponent: player_statistics(opponent)
	  }

	  player_game_record = game.game_players.find_by!(player: @player)
	  opponent_game_record = game.game_players.find_by!(player: opponent)

	  post login_path, params: {
	    email: @player.email,
	    password: "password"
	  }

	  assert_difference("Deck.count", -1) do
	    delete deck_path(@deck)
	  end

	  assert_redirected_to decks_path

	  game.reload

	  assert Game.exists?(game.id)
	  assert game.finished?

	  assert_equal original_result, game.state.fetch("result")

	  assert GamePlayer.exists?(player_game_record.id)
	  assert GamePlayer.exists?(opponent_game_record.id)

	  assert_nil player_game_record.reload.deck_id
	  assert_equal opponent_deck.id, opponent_game_record.reload.deck_id

	  assert_equal original_statistics[:player], player_statistics(@player)
	  assert_equal original_statistics[:opponent], player_statistics(opponent)
	end
	
	test "logged in player can destroy their deck" do
		post login_path, params: {
			email: @player.email,
			password: "password"
		}

		assert_difference("Deck.count", -1) do
			delete deck_path(@deck)
		end

		assert_redirected_to decks_path
	end
	
	test "logged in player cannot destroy another player's deck" do
		other_player = create_player(email: "other@example.com")
		StarterDecks::Create.call(other_player)
		other_deck = other_player.decks.first

		post login_path, params: {
			email: @player.email,
			password: "password"
		}

		assert_no_difference("Deck.count") do
			delete deck_path(other_deck)
		end

		assert_response :not_found
	end
	
	test "guest cannot open new deck page" do
		get play_path

		get new_deck_path

		assert_response :forbidden
	end

	test "guest cannot edit a deck" do
		get play_path

		guest = Player.find(session[:player_id])
		deck = guest.decks.first

		get edit_deck_path(deck)

		assert_response :forbidden
	end

	test "guest cannot update a deck" do
		get play_path

		guest = Player.find(session[:player_id])
		deck = guest.decks.first

		patch deck_path(deck), params: {
			deck: {
				name: "Guest Modified Deck"
			}
		}

		assert_response :forbidden

		assert_equal deck.name, deck.reload.name
	end

	test "guest cannot destroy a deck" do
		get play_path

		guest = Player.find(session[:player_id])
		deck = guest.decks.first

		assert_no_difference("Deck.count") do
			delete deck_path(deck)
		end

		assert_response :forbidden
		assert Deck.exists?(deck.id)
	end

	private

	def create_started_pvp_game(first_player:, first_deck:, second_player:, second_deck:)
	  game = Game.create!(
	    mode: "pvp",
	    status: "waiting"
	  )

	  [
	    [first_player, first_deck],
	    [second_player, second_deck]
	  ].each do |player, deck|
	    game.game_players.create!(
	      player: player,
	      nation: deck.nation,
	      deck: deck,
	      headquarters_card: deck.headquarters_card
	    )
	  end

	  GameEngine::StartGame.call(game)

	  game.reload
	end

	def surrender_game!(game:, player:)
	  action = DecisionProviders::Human.new(
	    player_id: player.id.to_s,
	    type: "surrender"
	  ).call

	  result = GameActionRunner.call(
	    game: game,
	    action: action
	  )

	  assert_predicate result, :success?, result.error

	  game.reload
	end

	def player_statistics(player)
	  player.reload.attributes.slice(
	    "battles_count",
	    "wins_count",
	    "losses_count"
	  )
	end
end
