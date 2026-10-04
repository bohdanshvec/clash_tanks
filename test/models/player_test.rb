require "test_helper"

class PlayerTest < ActiveSupport::TestCase
	test "has many decks" do
		player = create_player
		nation = Nation.create!(name: "СССР", code: "ussr")

		deck = create_deck(
		  player: player,
		  nation: nation,
		  name: "Основная колода"
		)

		assert_includes player.decks, deck
	end

  test "accepts valid email" do
    player = Player.new(
      email: "player@example.com",
      password: "password"
    )

    assert player.valid?
  end

  test "rejects invalid email" do
    player = Player.new(
      email: "invalid-email",
      password: "password"
    )

    assert_not player.valid?
    assert player.errors[:email].present?
  end

  test "normalizes email" do
    player = Player.create!(
      email: "  Player@Example.COM  ",
      password: "password"
    )

    assert_equal "player@example.com", player.email
  end

  test "rejects duplicate email" do
    create_player(email: "player@example.com")

    duplicate = Player.new(
      email: "player@example.com",
      password: "password"
    )

    assert_not duplicate.valid?
    assert duplicate.errors[:email].present?
  end

  test "rejects password shorter than 8 characters" do
    player = Player.new(
      email: "player@example.com",
      password: "1234567"
    )

    assert_not player.valid?
    assert player.errors[:password].present?
  end
  
	test "existing player with short password can still authenticate" do
		player = Player.new(
		  email: "legacy@example.com",
		  password_digest: BCrypt::Password.create("1234567")
		)
		player.save!(validate: false)

		assert player.authenticate("1234567")
	end
end
