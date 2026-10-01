require "test_helper"

class ApplicationControllerTest < ActionDispatch::IntegrationTest
  test "current_player is nil without a session" do
    get root_path

    assert_response :success
  end

  test "logged in player is available through current_player" do
    player = create_player(
      email: "player@example.com",
      password: "password"
    )

    post login_path, params: {
      email: player.email,
      password: "password"
    }

    get root_path

    assert_response :success
    assert_equal player.id, controller.send(:current_player).id
  end

  test "current_player_id comes from session" do
    player = create_player(
      email: "player@example.com",
      password: "password"
    )

    post login_path, params: {
      email: player.email,
      password: "password"
    }

    get root_path

    assert_equal player.id.to_s, controller.send(:current_player_id)
  end
end
