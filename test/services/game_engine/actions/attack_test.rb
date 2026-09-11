require "test_helper"

class GameEngine::Actions::AttackTest < ActiveSupport::TestCase
  PLAYER_ID = 1
  OPPONENT_ID = 2

  def setup
    @state = GameEngine::GameState.initial(
      current_player_id: PLAYER_ID,
      participants: [
        { player_id: PLAYER_ID, nation_id: 10 },
        { player_id: OPPONENT_ID, nation_id: 20 }
      ]
    )

    add_test_headquarters_stats

    @state["field"][1][1] = {
      "type" => "technique",
      "card_id" => 15,
      "player_id" => PLAYER_ID,
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

    @state["field"][1][2] = {
      "type" => "technique",
      "card_id" => 20,
      "player_id" => OPPONENT_ID,
      "technique_type" => "medium_tank",
      "hp" => 10,
      "firepower" => 3,
      "fuel" => 2,
      "attack_range" => 1,
      "movement_count" => 1,
      "movement_type" => "diagonal",
      "has_attacked" => false,
      "has_counterattacked" => false
    }
  end

  def add_test_headquarters_stats
    @state["field"][2][0].merge!(
      "hp" => 20,
      "firepower" => 4,
      "fuel" => 3,
      "has_attacked" => false
    )

    @state["field"][0][4].merge!(
      "hp" => 20,
      "firepower" => 4,
      "fuel" => 3,
      "has_attacked" => false
    )
  end

  test "attacks adjacent technique" do
    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [1, 1],
        target: [1, 2]
      }
    )

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert result.success?
    assert_equal 6, result.state["field"][1][2]["hp"]
    assert result.state["field"][1][1]["has_attacked"]
  end

  test "does not allow attack when it is not player's turn" do
    @state["current_player_id"] = OPPONENT_ID

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [1, 1],
        target: [1, 2]
      }
    )

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert_not result.success?
    assert_equal "It is not player's turn", result.error
  end

  test "does not allow attacking with enemy technique" do
    @state["field"][1][1]["player_id"] = OPPONENT_ID

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [1, 1],
        target: [1, 2]
      }
    )

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert_not result.success?
    assert_equal "Attacker does not belong to player", result.error
  end

  test "does not allow attacking empty target" do
    @state["field"][1][2] = nil

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [1, 1],
        target: [1, 2]
      }
    )

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert_not result.success?
    assert_equal "Target cell is empty", result.error
  end

  test "does not allow attacking from empty cell" do
    @state["field"][1][1] = nil

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [1, 1],
        target: [1, 2]
      }
    )

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert_not result.success?
    assert_equal "Attacker cell is empty", result.error
  end

  test "does not allow invalid coordinates" do
    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [5, 5],
        target: [1, 2]
      }
    )

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert_not result.success?
    assert_equal "Invalid coordinates", result.error
  end

  test "does not allow attack outside attack range" do
    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [1, 1],
        target: [1, 3]
      }
    )

    @state["field"][1][3] = {
      "type" => "technique",
      "card_id" => 21,
      "player_id" => OPPONENT_ID,
      "technique_type" => "medium_tank",
      "hp" => 10,
      "firepower" => 3,
      "attack_range" => 1,
      "has_attacked" => false,
      "has_counterattacked" => false
    }

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert_not result.success?
    assert_equal "Invalid attack range", result.error
  end

  test "does not allow attacking twice in one turn" do
    first_action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [1, 1],
        target: [1, 2]
      }
    )

    first_result = GameEngine::Actions::Attack.new(@state, first_action).call

    assert first_result.success?

    second_action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [1, 1],
        target: [1, 2]
      }
    )

    second_result = GameEngine::Actions::Attack.new(
      first_result.state,
      second_action
    ).call

    assert_not second_result.success?
    assert_equal "Technique has already attacked", second_result.error
  end

  test "destroys target when hp reaches zero" do
    @state["field"][1][2]["hp"] = 4

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [1, 1],
        target: [1, 2]
      }
    )

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert result.success?
    assert_nil result.state["field"][1][2]
  end

  test "performs counterattack after surviving adjacent attack" do
    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [1, 1],
        target: [1, 2]
      }
    )

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert result.success?
    assert_equal 7, result.state["field"][1][1]["hp"]
    assert result.state["field"][1][2]["has_counterattacked"]
  end

  test "does not counterattack twice" do
    @state["field"][1][2]["has_counterattacked"] = true

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [1, 1],
        target: [1, 2]
      }
    )

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert result.success?
    assert_equal 10, result.state["field"][1][1]["hp"]
  end

  test "counterattack can destroy attacker" do
    @state["field"][1][1]["hp"] = 3

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [1, 1],
        target: [1, 2]
      }
    )

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert result.success?
    assert_nil result.state["field"][1][1]
  end

	test "does not counterattack when target is not adjacent" do
		@state["field"][1][2] = nil

		@state["field"][1][3] = {
		  "type" => "technique",
		  "card_id" => 20,
		  "player_id" => OPPONENT_ID,
		  "technique_type" => "medium_tank",
		  "hp" => 10,
		  "firepower" => 3,
		  "attack_range" => 1,
		  "movement_count" => 1,
		  "movement_type" => "diagonal",
		  "has_attacked" => false,
		  "has_counterattacked" => false
		}

		@state["field"][1][1]["attack_range"] = 2

		action = GameEngine::Action.new(
		  player_id: PLAYER_ID,
		  type: "attack",
		  payload: {
		    attacker: [1, 1],
		    target: [1, 3]
		  }
		)

		result = GameEngine::Actions::Attack.new(@state, action).call

		assert result.success?
		assert_equal 10, result.state["field"][1][1]["hp"]
		assert_equal false, result.state["field"][1][3]["has_counterattacked"]
	end
	
  test "headquarters attacks enemy headquarters without counterattack" do
    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [2, 0],
        target: [0, 4]
      }
    )

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert result.success?
    assert_equal 16, result.state["field"][0][4]["hp"]
    assert result.state["field"][2][0]["has_attacked"]
  end

  test "headquarters attacks enemy technique on bridgehead" do
    @state["field"][1][4] = {
      "type" => "technique",
      "card_id" => 30,
      "player_id" => OPPONENT_ID,
      "technique_type" => "medium_tank",
      "hp" => 10,
      "firepower" => 3,
      "attack_range" => 1,
      "has_attacked" => false,
      "has_counterattacked" => false
    }

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [2, 0],
        target: [1, 4]
      }
    )

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert_not result.success?
    assert_equal "Technique is out of headquarters attack range", result.error
  end

	test "headquarters attacks enemy technique near allied technique" do
		@state["field"][1][3] = {
		  "type" => "technique",
		  "card_id" => 31,
		  "player_id" => PLAYER_ID,
		  "technique_type" => "medium_tank",
		  "hp" => 10,
		  "firepower" => 3,
		  "attack_range" => 1,
		  "has_attacked" => false,
		  "has_counterattacked" => false
		}

		@state["field"][1][4] = {
		  "type" => "technique",
		  "card_id" => 30,
		  "player_id" => OPPONENT_ID,
		  "technique_type" => "medium_tank",
		  "hp" => 10,
		  "firepower" => 3,
		  "attack_range" => 1,
		  "has_attacked" => false,
		  "has_counterattacked" => false
		}

		action = GameEngine::Action.new(
		  player_id: PLAYER_ID,
		  type: "attack",
		  payload: {
		    attacker: [2, 0],
		    target: [1, 4]
		  }
		)

		result = GameEngine::Actions::Attack.new(@state, action).call

		assert result.success?
		assert_equal 6, result.state["field"][1][4]["hp"]
		assert result.state["field"][2][0]["has_attacked"]
	end

  test "headquarters cannot attack distant technique without support" do
    @state["field"][0][3] = {
      "type" => "technique",
      "card_id" => 30,
      "player_id" => OPPONENT_ID,
      "technique_type" => "medium_tank",
      "hp" => 10,
      "firepower" => 3,
      "attack_range" => 1,
      "has_attacked" => false,
      "has_counterattacked" => false
    }

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [2, 0],
        target: [0, 3]
      }
    )

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert_not result.success?
    assert_equal "Technique is out of headquarters attack range", result.error
  end
  
  test "rejects invalid attacker type" do
    @state["field"][1][1]["type"] = "unknown"

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [1, 1],
        target: [1, 2]
      }
    )

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert_not result.success?
    assert_equal "Invalid attacker type", result.error
  end

  test "PTSAU shoots first when attacked by ordinary tank" do
    @state["field"][1][2]["technique_type"] = "tank_destroyer"

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [1, 1],
        target: [1, 2]
      }
    )

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert result.success?
    assert_equal 7, result.state["field"][1][1]["hp"]
    assert_equal 6, result.state["field"][1][2]["hp"]
  end

  test "PTSAU does not counterattack after shooting first" do
    @state["field"][1][2]["technique_type"] = "tank_destroyer"

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [1, 1],
        target: [1, 2]
      }
    )

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert result.success?
    refute result.state["field"][1][2]["has_counterattacked"]
  end

  test "PTSAU versus PTSAU attacker shoots first" do
    @state["field"][1][1]["technique_type"] = "tank_destroyer"
    @state["field"][1][2]["technique_type"] = "tank_destroyer"

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [1, 1],
        target: [1, 2]
      }
    )

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert result.success?
    assert_equal 7, result.state["field"][1][1]["hp"]
    assert_equal 6, result.state["field"][1][2]["hp"]
  end

  test "does not modify original state" do
    original_state = Marshal.load(Marshal.dump(@state))

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [1, 1],
        target: [1, 2]
      }
    )

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert result.success?
    assert_equal original_state, @state
  end
end
