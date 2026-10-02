require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
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
