require "test_helper"

class GameEngine::Turns::PreparePlayerTest < ActiveSupport::TestCase
  PLAYER_ID = 1
  OPPONENT_ID = 2

  def setup
    @state = GameEngine::GameState.initial(
      current_player_id: PLAYER_ID,
      participants: [
        headquarters_participant(player_id: PLAYER_ID, nation_id: 10),
        headquarters_participant(player_id: OPPONENT_ID, nation_id: 20)
      ]
    )

    @state["field"][1][1] = {
      "type" => "technique",
      "card_id" => 15,
      "player_id" => PLAYER_ID,
      "technique_type" => "medium_tank",
      "hp" => 10,
      "firepower" => 4,
      "fuel" => 2,
      "attack_range" => 1,
      "movement_count" => 0,
      "movement_limit" => 1,
      "movement_type" => "diagonal",
      "has_attacked" => true,
      "has_counterattacked" => true
    }

    @state["field"][1][2] = {
      "type" => "technique",
      "card_id" => 16,
      "player_id" => PLAYER_ID,
      "technique_type" => "light_tank",
      "hp" => 10,
      "firepower" => 4,
      "fuel" => 3,
      "attack_range" => 1,
      "movement_count" => 0,
      "movement_limit" => 2,
      "movement_type" => "orthogonal",
      "has_attacked" => true,
      "has_counterattacked" => true
    }

    @state["field"][0][3] = {
      "type" => "technique",
      "card_id" => 17,
      "player_id" => OPPONENT_ID,
      "technique_type" => "medium_tank",
      "hp" => 10,
      "firepower" => 4,
      "fuel" => 7,
      "attack_range" => 1,
      "movement_count" => 0,
      "movement_limit" => 1,
      "movement_type" => "diagonal",
      "has_attacked" => true,
      "has_counterattacked" => true
    }

    @state["players"][PLAYER_ID.to_s]["platoons"][0] = {
      "type" => "platoon",
      "card_id" => 30,
      "player_id" => PLAYER_ID,
      "firepower" => 5,
      "hp" => 10,
      "armor" => 3,
      "fuel" => 3
    }
  end

  test "restores movement for player's techniques" do
    result = GameEngine::Turns::PreparePlayer.call(
      state: @state,
      player_id: PLAYER_ID
    )

    assert_equal 1, result["field"][1][1]["movement_count"]
    assert_equal 2, result["field"][1][2]["movement_count"]
  end

  test "resets attack flags for player's techniques" do
    result = GameEngine::Turns::PreparePlayer.call(
      state: @state,
      player_id: PLAYER_ID
    )

    assert_not result["field"][1][1]["has_attacked"]
    assert_not result["field"][1][1]["has_counterattacked"]

    assert_not result["field"][1][2]["has_attacked"]
    assert_not result["field"][1][2]["has_counterattacked"]
  end

  test "does not reset opponent's techniques" do
    result = GameEngine::Turns::PreparePlayer.call(
      state: @state,
      player_id: PLAYER_ID
    )

    opponent_technique = result["field"][0][3]

    assert_equal 0, opponent_technique["movement_count"]
    assert opponent_technique["has_attacked"]
    assert opponent_technique["has_counterattacked"]
  end

  test "calculates fuel for prepared player" do
    result = GameEngine::Turns::PreparePlayer.call(
      state: @state,
      player_id: PLAYER_ID
    )

    # HQ 5 + Technique 2 + Technique 3 + Platoon 3
    assert_equal 13, result["players"][PLAYER_ID.to_s]["resources"]
  end

  test "does not modify original state" do
    original_state = Marshal.load(Marshal.dump(@state))

    result = GameEngine::Turns::PreparePlayer.call(
      state: @state,
      player_id: PLAYER_ID
    )

    assert_equal original_state, @state
    refute_same @state, result
  end
end
