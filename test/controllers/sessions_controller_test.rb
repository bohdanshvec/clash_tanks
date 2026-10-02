require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "renders login form" do
    get login_path

    assert_response :success
    assert_select "form"
    assert_select "input[name='email']"
    assert_select "input[name='password']"
  end

  test "logs in player with valid credentials" do
    player = create_player(
      email: "player@example.com",
      password: "password"
    )

    post login_path, params: {
      email: "player@example.com",
      password: "password"
    }

    assert_equal player.id, session[:player_id]
    assert_redirected_to root_path
  end

  test "logs in player with normalized email" do
    player = create_player(
      email: "player@example.com",
      password: "password"
    )

    post login_path, params: {
      email: "  PLAYER@EXAMPLE.COM  ",
      password: "password"
    }

    assert_equal player.id, session[:player_id]
    assert_redirected_to root_path
  end

  test "does not log in player with invalid password" do
    player = create_player(
      email: "player@example.com",
      password: "password"
    )

    post login_path, params: {
      email: player.email,
      password: "wrong-password"
    }

    assert_nil session[:player_id]
    assert_response :unprocessable_entity
  end

  test "does not log in unknown player" do
    post login_path, params: {
      email: "unknown@example.com",
      password: "password"
    }

    assert_nil session[:player_id]
    assert_response :unprocessable_entity
  end
end
