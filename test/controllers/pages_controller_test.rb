require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.load_seed
  end

  test "guest can access home" do
    get root_path

    assert_response :success
  end

  test "guest can access rules" do
    get rules_path

    assert_response :success
  end

  test "guest can access play" do
    get play_path

    assert_response :success
  end

  test "guest can access decks" do
    get decks_path

    assert_response :success
  end

  test "guest sees three starter decks" do
    get decks_path

    assert_response :success

    assert_select ".deck-card", count: 3

    assert_select ".deck-card", text: /Operation „Weiß“/
    assert_select ".deck-card", text: /Second front/
    assert_select ".deck-card", text: /Западный фронт/
  end

  test "guest does not create any players or decks" do
    assert_no_difference("Player.count") do
      assert_no_difference("Deck.count") do
        get decks_path
      end
    end

    assert_response :success
  end

  test "logged in player sees only their decks" do
    player = create_player(email: "player@example.com")
    StarterDecks::Create.call(player)

    other_player = create_player(email: "other@example.com")
    StarterDecks::Create.call(other_player)

    post login_path, params: {
      email: player.email,
      password: "password"
    }

    get decks_path

    assert_response :success

    assert_select ".deck-card", count: 3

    assert_select ".deck-card", text: /Operation „Weiß“/
    assert_select ".deck-card", text: /Second front/
    assert_select ".deck-card", text: /Западный фронт/
  end

  test "logged in player can access statistics" do
    player = create_player

    post login_path, params: {
      email: player.email,
      password: "password"
    }

    get statistics_path

    assert_response :success
  end
  
	test "logged in player sees only complete decks on play page" do
		player = create_player
		complete_deck = StarterDecks::Create.call(player).first

		incomplete_deck = player.decks.create!(
		  name: "Incomplete",
		  nation: complete_deck.nation,
		  headquarters_card: complete_deck.headquarters_card
		)

		post login_path, params: {
		  email: player.email,
		  password: "password"
		}

		get play_path

		assert_response :success
		assert_select ".deck-card", count: 3
		assert_select ".deck-card", text: /Operation „Weiß“/
		assert_select ".deck-card", text: /Second front/
		assert_select ".deck-card", text: /Западный фронт/
		assert_select ".deck-card", text: /Incomplete/, count: 0
	end
end
