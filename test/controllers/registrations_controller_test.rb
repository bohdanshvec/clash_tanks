require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.load_seed
  end

  test "renders registration form" do
    get register_path

    assert_response :success
    assert_select "form"
    assert_select "input[name='player[email]']"
    assert_select "input[name='player[name]']"
    assert_select "input[name='player[password]']"
    assert_select "input[name='player[password_confirmation]']"
  end

  test "creates a player with valid data" do
    assert_difference("Player.count", 1) do
      post register_path, params: {
        player: {
          email: "new-player@example.com",
          name: "New Player",
          password: "password",
          password_confirmation: "password"
        }
      }
    end

    player = Player.find_by!(email: "new-player@example.com")

    assert_equal "New Player", player.name
    assert player.authenticate("password")
    assert_redirected_to root_path
  end
  
  test "creates three starter decks with ten cards each" do
    post register_path, params: {
      player: {
        email: "starter-decks@example.com",
        name: "Starter Decks Player",
        password: "password",
        password_confirmation: "password"
      }
    }

    player = Player.find_by!(email: "starter-decks@example.com")
    decks = player.decks.includes(:deck_cards, :headquarters_card).order(:name)

    assert_equal 3, decks.size

    assert_equal(
      [
        "Operation „Weiß“",
        "Second front",
        "Западный фронт"
      ],
      decks.map(&:name)
    )

    decks.each do |deck|
      assert deck.complete?
      assert_equal 10, deck.card_count
      assert_equal 10, deck.deck_cards.size
      assert_equal 1, deck.deck_cards.map(&:quantity).uniq.size
      assert_equal 1, deck.deck_cards.first.quantity
      assert_equal "headquarters", deck.headquarters_card.card_type
      assert_equal deck.nation_id, deck.headquarters_card.nation_id
    end

    assert_redirected_to root_path
  end

  test "rolls back player creation when starter decks cannot be created" do
    original_call = StarterDecks::Create.method(:call)

    StarterDecks::Create.define_singleton_method(:call) do |_player|
      raise ActiveRecord::RecordInvalid.new(Deck.new)
    end

    assert_no_difference("Player.count") do
      post register_path, params: {
        player: {
          email: "rollback@example.com",
          name: "Rollback Player",
          password: "password",
          password_confirmation: "password"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_nil Player.find_by(email: "rollback@example.com")
  ensure
    StarterDecks::Create.define_singleton_method(:call, original_call)
  end
  
  test "normalizes email during registration" do
    assert_difference("Player.count", 1) do
      post register_path, params: {
        player: {
          email: "  New-Player@Example.COM  ",
          name: "New Player",
          password: "password",
          password_confirmation: "password"
        }
      }
    end

    player = Player.find_by!(email: "new-player@example.com")

    assert_equal "new-player@example.com", player.email
    assert_redirected_to root_path
  end

  test "does not create a player with empty email" do
    assert_no_difference("Player.count") do
      post register_path, params: {
        player: {
          email: "",
          name: "New Player",
          password: "password",
          password_confirmation: "password"
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "does not create a player with invalid email" do
    assert_no_difference("Player.count") do
      post register_path, params: {
        player: {
          email: "invalid-email",
          name: "New Player",
          password: "password",
          password_confirmation: "password"
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "does not create a player with short password" do
    assert_no_difference("Player.count") do
      post register_path, params: {
        player: {
          email: "new-player@example.com",
          name: "New Player",
          password: "1234567",
          password_confirmation: "1234567"
        }
      }
    end

    assert_response :unprocessable_entity
  end
end
