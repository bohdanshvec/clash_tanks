require "test_helper"

class GameEngine::StartGameTest < ActiveSupport::TestCase
  test "starts a waiting game with two players" do
    game = Game.create!
    player1 = Player.create!
    player2 = Player.create!

    nation1 = Nation.create!(
      name: "Nation 1",
      code: "nation_1"
    )

    nation2 = Nation.create!(
      name: "Nation 2",
      code: "nation_2"
    )

    GamePlayer.create!(
      game: game,
      player: player1,
      nation: nation1
    )

    GamePlayer.create!(
      game: game,
      player: player2,
      nation: nation2
    )

    GameEngine::StartGame.call(game)

    game.reload

    assert game.started?
    assert_equal 1, game.state["turn_number"]
    assert_includes [player1.id, player2.id], game.state["current_player_id"]

    assert_equal(
      [player1.id.to_s, player2.id.to_s].sort,
      game.state["players"].keys.sort
    )

    assert_equal(
      nation1.id,
      game.state["players"][player1.id.to_s]["nation_id"]
    )

    assert_equal(
      nation2.id,
      game.state["players"][player2.id.to_s]["nation_id"]
    )

    assert_equal(
      {
        "type" => "headquarters",
        "player_id" => player1.id,
        "nation_id" => nation1.id
      },
      game.state["field"][2][0]
    )

    assert_equal(
      {
        "type" => "headquarters",
        "player_id" => player2.id,
        "nation_id" => nation2.id
      },
      game.state["field"][0][4]
    )
  end

  test "does not start a game with one player" do
    game = Game.create!
    player = Player.create!

    nation = Nation.create!(
      name: "Nation 1",
      code: "nation_1"
    )

    GamePlayer.create!(
      game: game,
      player: player,
      nation: nation
    )

    assert_raises(ArgumentError, "Game must have exactly two players") do
      GameEngine::StartGame.call(game)
    end

    game.reload

    assert game.waiting?
    assert_nil game.state
  end

  test "does not start a game that has already started" do
    game = Game.create!
    player1 = Player.create!
    player2 = Player.create!

    nation1 = Nation.create!(
      name: "Nation 1",
      code: "nation_1"
    )

    nation2 = Nation.create!(
      name: "Nation 2",
      code: "nation_2"
    )

    GamePlayer.create!(
      game: game,
      player: player1,
      nation: nation1
    )

    GamePlayer.create!(
      game: game,
      player: player2,
      nation: nation2
    )

    GameEngine::StartGame.call(game)

    assert_raises(ArgumentError, "Game must be waiting") do
      GameEngine::StartGame.call(game)
    end
  end
end
