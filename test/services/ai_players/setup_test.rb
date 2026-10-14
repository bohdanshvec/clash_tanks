require "test_helper"

class AiPlayers::SetupTest < ActiveSupport::TestCase
  test "creates a permanent AI player" do
    player = AiPlayers::Setup.call

    assert player.persisted?
    assert player.ai?
    refute player.guest?
    assert_equal AiPlayers::Setup::AI_EMAIL, player.email
    assert_equal AiPlayers::Setup::AI_NAME, player.name
  end

  test "reuses the existing AI player on repeated calls" do
    first_player = AiPlayers::Setup.call

    assert_no_difference -> { Player.where(ai: true).count } do
      second_player = AiPlayers::Setup.call

      assert_equal first_player.id, second_player.id
    end
  end
end
