require "test_helper"

class GameEngine::Actions::EndTurnTest < ActiveSupport::TestCase
  PLAYER_ID = 1
  OPPONENT_ID = 2

  def setup
    @started_at = Time.current.change(usec: 0)

    @state = GameEngine::GameState.initial(
      current_player_id: PLAYER_ID,
      participants: [
        headquarters_participant(player_id: PLAYER_ID, nation_id: 10),
        headquarters_participant(player_id: OPPONENT_ID, nation_id: 20)
      ]
    )

    @state["turn_started_at"] = @started_at.iso8601
  end

  test "ends current player's turn" do
    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "end_turn"
    )

    result = GameEngine::Actions::EndTurn.new(@state, action).call

    assert result.success?
    assert_equal 2, result.state["turn_number"]
    assert_equal OPPONENT_ID, result.state["current_player_id"]
    assert_equal [{ type: "turn_ended" }], result.events
  end

  test "does not allow ending opponent's turn" do
    action = GameEngine::Action.new(
      player_id: OPPONENT_ID,
      type: "end_turn"
    )

    result = GameEngine::Actions::EndTurn.new(@state, action).call

    assert_not result.success?
    assert_equal "It is not player's turn", result.error
  end

  test "does not allow unknown player to end turn" do
    action = GameEngine::Action.new(
      player_id: 999,
      type: "end_turn"
    )

    result = GameEngine::Actions::EndTurn.new(@state, action).call

    assert_not result.success?
    assert_equal "Player does not exist", result.error
  end

  test "does not modify original state" do
    original_state = Marshal.load(Marshal.dump(@state))

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "end_turn"
    )

    result = GameEngine::Actions::EndTurn.new(@state, action).call

    assert result.success?
    assert_equal original_state, @state
  end

  test "turn alternates back to first player" do
    first_action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "end_turn"
    )

    first_result = GameEngine::Actions::EndTurn.new(
      @state,
      first_action
    ).call

    second_action = GameEngine::Action.new(
      player_id: OPPONENT_ID,
      type: "end_turn"
    )

    second_result = GameEngine::Actions::EndTurn.new(
      first_result.state,
      second_action
    ).call

    assert second_result.success?
    assert_equal 3, second_result.state["turn_number"]
    assert_equal PLAYER_ID, second_result.state["current_player_id"]
  end

  test "deducts elapsed time from current player's remaining time" do
    current_time = @started_at + 30

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "end_turn"
    )

    result = GameEngine::Actions::EndTurn.new(
      @state,
      action,
      current_time: current_time
    ).call

    assert result.success?
    assert_equal 570, result.state["players"][PLAYER_ID.to_s]["remaining_time"]
    assert_equal current_time.iso8601, result.state["turn_started_at"]
    assert_equal OPPONENT_ID, result.state["current_player_id"]
  end

	test "finishes game when ending turn after time expires" do
		current_time = @started_at + 600

		action = GameEngine::Action.new(
		  player_id: PLAYER_ID,
		  type: "end_turn"
		)

		result = GameEngine::Actions::EndTurn.new(
		  @state,
		  action,
		  current_time: current_time
		).call

		assert result.success?

		assert_equal "finished", result.state["status"]

		assert_equal(
		  {
		    "winner_id" => OPPONENT_ID.to_s,
		    "loser_id" => PLAYER_ID.to_s,
		    "reason" => "time_expired"
		  },
		  result.state["result"]
		)

		assert_equal(
		  [
		    {
		      type: "game_finished",
		      winner_id: OPPONENT_ID.to_s,
		      loser_id: PLAYER_ID.to_s,
		      reason: "time_expired"
		    }
		  ],
		  result.events
		)
	end
  
	test "calculates fuel for the player whose turn starts" do
		@state["field"][1][0] = {
		  "type" => "technique",
		  "card_id" => 100,
		  "player_id" => OPPONENT_ID,
		  "nation_id" => 20,
		  "name" => "Enemy Technique",
		  "technique_type" => "medium_tank",
		  "hp" => 10,
		  "firepower" => 4,
		  "fuel" => 2,
		  "attack_range" => 1,
		  "movement_count" => 1,
		  "movement_type" => "diagonal",
		  "has_attacked" => false,
		  "has_counterattacked" => false
		}

		@state["players"][OPPONENT_ID.to_s]["platoons"][0] = {
		  "type" => "platoon",
		  "card_id" => 200,
		  "player_id" => OPPONENT_ID,
		  "nation_id" => 20,
		  "name" => "Enemy Platoon",
		  "firepower" => 5,
		  "hp" => 10,
		  "armor" => 3,
		  "fuel" => 3
		}

		action = GameEngine::Action.new(
		  player_id: PLAYER_ID,
		  type: "end_turn"
		)

		result = GameEngine::Actions::EndTurn.new(@state, action).call

		assert result.success?
		assert_equal 10, result.state["players"][OPPONENT_ID.to_s]["resources"]
	end

	test "replaces new player's resources with calculated fuel" do
		@state["players"][OPPONENT_ID.to_s]["resources"] = 99

		action = GameEngine::Action.new(
		  player_id: PLAYER_ID,
		  type: "end_turn"
		)

		result = GameEngine::Actions::EndTurn.new(@state, action).call

		assert result.success?
		assert_equal 5, result.state["players"][OPPONENT_ID.to_s]["resources"]
	end
end
