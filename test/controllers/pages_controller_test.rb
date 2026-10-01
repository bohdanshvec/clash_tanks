require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
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

  test "guest is redirected from statistics" do
    get statistics_path

    assert_redirected_to root_path
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
end
