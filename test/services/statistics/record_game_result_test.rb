require "test_helper"

class Statistics::RecordGameResultTest < ActiveSupport::TestCase
  setup do
    @winner = create_player
    @loser = create_player
  end

  test "records statistics for two registered players" do
    game = finished_game(
      winner: @winner,
      loser: @loser
    )

    Statistics::RecordGameResult.call(game: game)

    assert_equal 1, @winner.reload.battles_count
    assert_equal 1, @winner.wins_count
    assert_equal 0, @winner.losses_count

    assert_equal 1, @loser.reload.battles_count
    assert_equal 0, @loser.wins_count
    assert_equal 1, @loser.losses_count
  end

  test "records victory against guest only for registered player" do
    @loser.update!(guest: true)

    game = finished_game(
      winner: @winner,
      loser: @loser
    )

    Statistics::RecordGameResult.call(game: game)

    assert_equal 1, @winner.reload.battles_count
    assert_equal 1, @winner.wins_count

    assert_equal 0, @loser.reload.battles_count
  end

  test "records defeat against guest only for registered player" do
    @winner.update!(guest: true)

    game = finished_game(
      winner: @winner,
      loser: @loser
    )

    Statistics::RecordGameResult.call(game: game)

    assert_equal 0, @winner.reload.battles_count

    assert_equal 1, @loser.reload.battles_count
    assert_equal 1, @loser.losses_count
  end

  test "does not record AI games" do
    game = finished_game(
      winner: @winner,
      loser: @loser,
      mode: "ai"
    )

    Statistics::RecordGameResult.call(game: game)

    assert_equal 0, @winner.reload.battles_count
    assert_equal 0, @loser.reload.battles_count
  end

  test "does not record statistics for two guests" do
    @winner.update!(guest: true)
    @loser.update!(guest: true)

    game = finished_game(
      winner: @winner,
      loser: @loser
    )

    Statistics::RecordGameResult.call(game: game)

    assert_equal 0, @winner.reload.battles_count
    assert_equal 0, @loser.reload.battles_count
  end

  test "calculates win rate with two decimal places" do
    @winner.update!(
      battles_count: 3,
      wins_count: 2,
      losses_count: 1
    )

    assert_equal 66.67, @winner.reload.win_rate
  end

  test "returns zero win rate without battles" do
    assert_equal 0.0, @winner.win_rate
  end

  test "orders leaders by wins and win rate" do
    @winner.update!(
      battles_count: 10,
      wins_count: 8,
      losses_count: 2
    )

    @loser.update!(
      battles_count: 20,
      wins_count: 8,
      losses_count: 12
    )

    leaders = Player.statistics_leaders.to_a

    assert_operator leaders.index(@winner), :<, leaders.index(@loser)
  end

  private

  def finished_game(winner:, loser:, mode: "pvp")
    winner_deck = create_complete_deck(player: winner)
    loser_deck = create_complete_deck(player: loser)

    game = Game.create!(
      status: "finished",
      mode: mode,
      state: {
        "status" => "finished",
        "players" => {
          winner.id.to_s => {},
          loser.id.to_s => {}
        },
        "result" => {
          "winner_id" => winner.id.to_s,
          "loser_id" => loser.id.to_s,
          "reason" => "surrender"
        }
      }
    )

    [
      [winner, winner_deck],
      [loser, loser_deck]
    ].each do |player, deck|
      game.game_players.create!(
        player: player,
        deck: deck,
        nation: deck.nation,
        headquarters_card: deck.headquarters_card
      )
    end

    game
  end
end
