require "test_helper"

class GameEngine::Actions::AttackTest < ActiveSupport::TestCase
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
      "has_attacked" => false,
      "has_counterattacked" => false
    )

    @state["field"][0][4].merge!(
      "hp" => 20,
      "firepower" => 4,
      "fuel" => 3,
      "has_attacked" => false,
      "has_counterattacked" => false
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

   test "headquarters cannot attack distant technique without spotting" do
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
  
	test "technique attacks enemy headquarters from adjacent cell" do
		@state["field"][0][3] = {
		  "type" => "technique",
		  "card_id" => 30,
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

		action = GameEngine::Action.new(
		  player_id: PLAYER_ID,
		  type: "attack",
		  payload: {
		    attacker: [0, 3],
		    target: [0, 4]
		  }
		)

		result = GameEngine::Actions::Attack.new(@state, action).call

		assert result.success?, result.error
		assert_equal 16, result.state["field"][0][4]["hp"]
		assert result.state["field"][0][3]["has_attacked"]
		assert result.state["field"][0][4]["has_counterattacked"]
		assert_equal 6, result.state["field"][0][3]["hp"]
	end

	test "technique does not counterattack after destroying enemy headquarters" do
		@state["field"][0][3] = {
		  "type" => "technique",
		  "card_id" => 30,
		  "player_id" => PLAYER_ID,
		  "technique_type" => "medium_tank",
		  "hp" => 10,
		  "firepower" => 25,
		  "fuel" => 2,
		  "attack_range" => 1,
		  "movement_count" => 1,
		  "movement_type" => "diagonal",
		  "has_attacked" => false,
		  "has_counterattacked" => false
		}

		action = GameEngine::Action.new(
		  player_id: PLAYER_ID,
		  type: "attack",
		  payload: {
		    attacker: [0, 3],
		    target: [0, 4]
		  }
		)

		result = GameEngine::Actions::Attack.new(@state, action).call

		assert result.success?, result.error
		assert_equal 0, result.state["field"][0][4]["hp"]
		assert_equal false, result.state["field"][0][3]["has_counterattacked"]
		assert_equal 10, result.state["field"][0][3]["hp"]
	end

  test "ordinary technique cannot attack enemy headquarters from distance" do
    @state["field"][1][1] = {
      "type" => "technique",
      "card_id" => 30,
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

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [1, 1],
        target: [0, 4]
      }
    )

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert_not result.success?
    assert_equal(
      "Technique cannot attack headquarters at this range",
      result.error
    )
  end

	test "SAU attacks enemy headquarters from distance with spotting" do
		@state["field"][1][4] = {
		  "type" => "technique",
		  "card_id" => 30,
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

		@state["field"][2][2] = {
		  "type" => "technique",
		  "card_id" => 31,
		  "player_id" => PLAYER_ID,
		  "technique_type" => "artillery",
		  "hp" => 10,
		  "firepower" => 4,
		  "fuel" => 2,
		  "attack_range" => 1,
		  "movement_count" => 1,
		  "movement_type" => "orthogonal",
		  "has_attacked" => false,
		  "has_counterattacked" => false
		}

		action = GameEngine::Action.new(
		  player_id: PLAYER_ID,
		  type: "attack",
		  payload: {
		    attacker: [2, 2],
		    target: [0, 4]
		  }
		)

		result = GameEngine::Actions::Attack.new(@state, action).call

		assert result.success?, result.error
		assert_equal 16, result.state["field"][0][4]["hp"]
		assert result.state["field"][2][2]["has_attacked"]
		assert_equal false, result.state["field"][0][4]["has_counterattacked"]
	end
  test "SAU attacks enemy headquarters from adjacent cell as normal attack" do
    @state["field"][1][4] = {
      "type" => "technique",
      "card_id" => 31,
      "player_id" => PLAYER_ID,
      "technique_type" => "artillery",
      "hp" => 10,
      "firepower" => 4,
      "fuel" => 2,
      "attack_range" => 1,
      "movement_count" => 1,
      "movement_type" => "orthogonal",
      "has_attacked" => false,
      "has_counterattacked" => false
    }

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [1, 4],
        target: [0, 4]
      }
    )

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert result.success?
    assert_equal 16, result.state["field"][0][4]["hp"]
    assert result.state["field"][0][4]["has_counterattacked"]
    assert_equal 6, result.state["field"][1][4]["hp"]
  end

	test "SAU cannot attack enemy headquarters from distance without spotting" do
		@state["field"][2][4] = {
		  "type" => "technique",
		  "card_id" => 31,
		  "player_id" => PLAYER_ID,
		  "technique_type" => "artillery",
		  "hp" => 10,
		  "firepower" => 4,
		  "fuel" => 2,
		  "attack_range" => 1,
		  "movement_count" => 1,
		  "movement_type" => "orthogonal",
		  "has_attacked" => false,
		  "has_counterattacked" => false
		}

		action = GameEngine::Action.new(
		  player_id: PLAYER_ID,
		  type: "attack",
		  payload: {
		    attacker: [2, 4],
		    target: [0, 4]
		  }
		)

		result = GameEngine::Actions::Attack.new(@state, action).call

		assert_not result.success?
		assert_equal(
		  "Technique cannot attack headquarters at this range",
		  result.error
		)
	end

  test "destroyed technique is moved to owner's graveyard" do
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

    graveyard = result.state["players"][OPPONENT_ID.to_s]["graveyard"]

    assert_equal 1, graveyard.size
    assert_equal 0, graveyard.first["hp"]
    assert_equal 20, graveyard.first["card_id"]
    assert_equal OPPONENT_ID, graveyard.first["player_id"]
  end

  test "attacker destroyed by counterattack is moved to owner's graveyard" do
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

    graveyard = result.state["players"][PLAYER_ID.to_s]["graveyard"]

    assert_equal 1, graveyard.size
    assert_equal 0, graveyard.first["hp"]
    assert_equal 15, graveyard.first["card_id"]
    assert_equal PLAYER_ID, graveyard.first["player_id"]
  end

  test "PTSAU destroyed before it can attack is moved to graveyard" do
    @state["field"][1][2]["technique_type"] = "tank_destroyer"
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
    assert_equal 10, result.state["field"][1][2]["hp"]

    graveyard = result.state["players"][PLAYER_ID.to_s]["graveyard"]

    assert_equal 1, graveyard.size
    assert_equal 0, graveyard.first["hp"]
    assert_equal 15, graveyard.first["card_id"]
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
  
  test "headquarters attack includes platoon firepower" do
    @state["players"][PLAYER_ID.to_s]["platoons"][0] = {
      "card_id" => 101,
      "player_id" => PLAYER_ID,
      "firepower" => 3,
      "hp" => 10
    }

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [2, 0],
        target: [0, 4]
      }
    )

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert result.success?, result.error

    # HQ firepower 4 + Platoon firepower 3 = 7
    assert_equal 13, result.state["field"][0][4]["hp"]

    # Platoon loses HP equal to its firepower
    assert_equal 7, result.state["players"][PLAYER_ID.to_s]["platoons"][0]["hp"]
  end

  test "headquarters attack includes firepower of multiple platoons" do
    @state["players"][PLAYER_ID.to_s]["platoons"][0] = {
      "card_id" => 101,
      "player_id" => PLAYER_ID,
      "firepower" => 2,
      "hp" => 10
    }

    @state["players"][PLAYER_ID.to_s]["platoons"][1] = {
      "card_id" => 102,
      "player_id" => PLAYER_ID,
      "firepower" => 3,
      "hp" => 10
    }

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [2, 0],
        target: [0, 4]
      }
    )

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert result.success?, result.error

    # HQ 4 + Platoon 2 + Platoon 3 = 9
    assert_equal 11, result.state["field"][0][4]["hp"]

    assert_equal 8, result.state["players"][PLAYER_ID.to_s]["platoons"][0]["hp"]
    assert_equal 7, result.state["players"][PLAYER_ID.to_s]["platoons"][1]["hp"]
  end

  test "destroyed platoon is moved to owner's graveyard and its slot becomes nil" do
    @state["players"][PLAYER_ID.to_s]["platoons"][0] = {
      "card_id" => 101,
      "player_id" => PLAYER_ID,
      "firepower" => 4,
      "hp" => 4
    }

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [2, 0],
        target: [0, 4]
      }
    )

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert result.success?, result.error

    assert_nil result.state["players"][PLAYER_ID.to_s]["platoons"][0]

    graveyard = result.state["players"][PLAYER_ID.to_s]["graveyard"]

    assert_equal 1, graveyard.size
    assert_equal 101, graveyard.first["card_id"]
    assert_equal PLAYER_ID, graveyard.first["player_id"]
    assert_equal 0, graveyard.first["hp"]
  end

  test "destroyed platoon does not shift other platoon slots" do
    @state["players"][PLAYER_ID.to_s]["platoons"][0] = {
      "card_id" => 101,
      "player_id" => PLAYER_ID,
      "firepower" => 4,
      "hp" => 4
    }

    @state["players"][PLAYER_ID.to_s]["platoons"][1] = {
      "card_id" => 102,
      "player_id" => PLAYER_ID,
      "firepower" => 2,
      "hp" => 10
    }

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [2, 0],
        target: [0, 4]
      }
    )

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert result.success?, result.error

    assert_nil result.state["players"][PLAYER_ID.to_s]["platoons"][0]
    assert_equal 102, result.state["players"][PLAYER_ID.to_s]["platoons"][1]["card_id"]
    assert_equal 8, result.state["players"][PLAYER_ID.to_s]["platoons"][1]["hp"]
  end

  test "nil platoon slots are ignored when calculating headquarters firepower" do
    @state["players"][PLAYER_ID.to_s]["platoons"][0] = nil

    @state["players"][PLAYER_ID.to_s]["platoons"][1] = {
      "card_id" => 102,
      "player_id" => PLAYER_ID,
      "firepower" => 3,
      "hp" => 10
    }

    @state["players"][PLAYER_ID.to_s]["platoons"][2] = nil

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [2, 0],
        target: [0, 4]
      }
    )

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert result.success?, result.error

    # HQ 4 + Platoon 3 = 7
    assert_equal 13, result.state["field"][0][4]["hp"]
    assert_equal 7, result.state["players"][PLAYER_ID.to_s]["platoons"][1]["hp"]
  end

  test "headquarters attack on technique also includes platoon firepower" do
    @state["players"][PLAYER_ID.to_s]["platoons"][0] = {
      "card_id" => 101,
      "player_id" => PLAYER_ID,
      "firepower" => 3,
      "hp" => 10
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

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [2, 0],
        target: [1, 4]
      }
    )

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert result.success?, result.error

    # HQ 4 + Platoon 3 = 7
    assert_equal 3, result.state["field"][1][4]["hp"]
    assert_equal 7, result.state["players"][PLAYER_ID.to_s]["platoons"][0]["hp"]
  end

  test "platoon changes do not modify original state" do
    @state["players"][PLAYER_ID.to_s]["platoons"][0] = {
      "card_id" => 101,
      "player_id" => PLAYER_ID,
      "firepower" => 3,
      "hp" => 10
    }

    original_state = Marshal.load(Marshal.dump(@state))

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "attack",
      payload: {
        attacker: [2, 0],
        target: [0, 4]
      }
    )

    result = GameEngine::Actions::Attack.new(@state, action).call

    assert result.success?, result.error
    assert_equal original_state, @state
  end
  
  test "platoon armor absorbs incoming headquarters damage" do
    state = @state

    state["players"]["2"]["platoons"][0] = {
      "type" => "platoon",
      "card_id" => 100,
      "player_id" => 2,
      "nation_id" => 20,
      "name" => "Пехотный взвод",
      "firepower" => 3,
      "hp" => 10,
      "armor" => 3,
      "fuel" => 2
    }

    state["field"][0][3] = state["field"][1][1].deep_dup
    state["field"][0][3]["firepower"] = 6

    action = GameEngine::Action.new(
      player_id: 1,
      type: "attack",
      payload: {
        attacker: [0, 3],
        target: [0, 4]
      }
    )

    result = GameEngine::Actions::Attack.new(state, action).call

    assert result.success?

    # 6 урона:
    # 3 поглощает Platoon, 3 получает HQ.
    assert_equal 7, result.state["players"]["2"]["platoons"][0]["hp"]
    assert_equal 17, result.state["field"][0][4]["hp"]
  end

  test "incoming headquarters damage cascades through platoons" do
    state = @state

    state["players"]["2"]["platoons"] = [
      {
        "type" => "platoon",
        "card_id" => 101,
        "player_id" => 2,
        "nation_id" => 20,
        "name" => "Взвод 1",
        "firepower" => 2,
        "hp" => 10,
        "armor" => 3,
        "fuel" => 2
      },
      {
        "type" => "platoon",
        "card_id" => 102,
        "player_id" => 2,
        "nation_id" => 20,
        "name" => "Взвод 2",
        "firepower" => 2,
        "hp" => 10,
        "armor" => 4,
        "fuel" => 2
      },
      nil,
      nil
    ]

    state["field"][0][3] = state["field"][1][1].deep_dup
    state["field"][0][3]["firepower"] = 10

    action = GameEngine::Action.new(
      player_id: 1,
      type: "attack",
      payload: {
        attacker: [0, 3],
        target: [0, 4]
      }
    )

    result = GameEngine::Actions::Attack.new(state, action).call

    assert result.success?

    # 10 урона:
    # Platoon 1 поглощает 3 -> HP 7.
    # Platoon 2 поглощает 4 -> HP 6.
    # Оставшиеся 3 получает HQ.
    assert_equal 7, result.state["players"]["2"]["platoons"][0]["hp"]
    assert_equal 6, result.state["players"]["2"]["platoons"][1]["hp"]
    assert_equal 17, result.state["field"][0][4]["hp"]
  end

  test "platoon is destroyed when incoming damage exceeds its hp" do
    state = @state

    state["players"]["2"]["platoons"][0] = {
      "type" => "platoon",
      "card_id" => 103,
      "player_id" => 2,
      "nation_id" => 20,
      "name" => "Пехотный взвод",
      "firepower" => 2,
      "hp" => 2,
      "armor" => 5,
      "fuel" => 2
    }

    state["field"][0][3] = state["field"][1][1].deep_dup
    state["field"][0][3]["firepower"] = 7

    action = GameEngine::Action.new(
      player_id: 1,
      type: "attack",
      payload: {
        attacker: [0, 3],
        target: [0, 4]
      }
    )

    result = GameEngine::Actions::Attack.new(state, action).call

    assert result.success?

    assert_nil result.state["players"]["2"]["platoons"][0]

    graveyard = result.state["players"]["2"]["graveyard"]

    destroyed = graveyard.find do |card|
      card["card_id"] == 103
    end

    assert_not_nil destroyed
    assert_equal 0, destroyed["hp"]

    # 7 урона:
    # Platoon поглощает 5 и уничтожается.
    # Оставшиеся 2 получает HQ.
    assert_equal 18, result.state["field"][0][4]["hp"]
  end
end
