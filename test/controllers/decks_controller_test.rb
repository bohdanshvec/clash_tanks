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

		assert_difference("Deck.count", 1) do
		  post decks_path, params: {
		    deck: {
		      name: "Моя колода",
		      headquarters_card_id: headquarters_card.id,
		      card_quantities: {}
		    }
		  }
		end

		assert_redirected_to decks_path

		deck = @player.decks.find_by!(name: "Моя колода")

		assert_equal headquarters_card.id, deck.headquarters_card_id
		assert_equal headquarters_card.nation_id, deck.nation_id
		assert_equal 0, deck.card_count
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
	
	test "logged in player cannot create a deck with more than ten cards" do
		post login_path, params: {
		  email: @player.email,
		  password: "password"
		}

		headquarters_card = @deck.headquarters_card

		cards = Card
		  .where(nation_id: headquarters_card.nation_id)
		  .where.not(card_type: "headquarters")
		  .limit(4)

		card_quantities = cards.index_with { 3 }

		assert_equal 12, card_quantities.values.sum

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
end
