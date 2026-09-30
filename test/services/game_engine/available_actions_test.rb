require "test_helper"

class GameEngine::AvailableActionsTest < ActiveSupport::TestCase
  test "returns empty result when player does not exist" do
    state = base_state

    result = GameEngine::AvailableActions.call(
      state: state,
      player_id: 999
    )

    assert_equal(
      {
        "field" => {},
        "hand" => {}
      },
      result
    )
  end

  test "returns empty result when it is not player's turn" do
    state = base_state
    state["current_player_id"] = "2"

    result = GameEngine::AvailableActions.call(
      state: state,
      player_id: 1
    )

    assert_equal(
      {
        "field" => {},
        "hand" => {}
      },
      result
    )
  end

  test "returns available moves for own technique" do
    state = base_state

    technique = technique(
      player_id: 1,
      movement_type: "orthogonal",
      movement_count: 1
    )

    state["field"][1][1] = technique

    result = GameEngine::AvailableActions.call(
      state: state,
      player_id: 1
    )

    actions = result["field"]["1,1"]

    assert_equal(
      [
        [0, 1],
        [1, 0],
        [1, 2],
        [2, 1]
      ],
      actions["moves"]
    )
  end

  test "does not return moves when technique has no movement left" do
    state = base_state

    state["field"][1][1] = technique(
      player_id: 1,
      movement_type: "orthogonal",
      movement_count: 0
    )

    result = GameEngine::AvailableActions.call(
      state: state,
      player_id: 1
    )

    assert_equal(
      [],
      result["field"]["1,1"]["moves"]
    )
  end

  test "returns diagonal movement for medium tank" do
    state = base_state

    state["field"][1][1] = technique(
      player_id: 1,
      movement_type: "diagonal",
      movement_count: 1
    )

    result = GameEngine::AvailableActions.call(
      state: state,
      player_id: 1
    )

    assert_equal(
      [
        [0, 0],
        [0, 1],
        [0, 2],
        [1, 0],
        [1, 2],
        [2, 1],
        [2, 2]
      ],
      result["field"]["1,1"]["moves"]
    )
  end

  test "does not return occupied cells as movement targets" do
    state = base_state

    state["field"][1][1] = technique(
      player_id: 1,
      movement_type: "orthogonal",
      movement_count: 1
    )

    state["field"][1][2] = technique(
      player_id: 2
    )

    result = GameEngine::AvailableActions.call(
      state: state,
      player_id: 1
    )

    refute_includes(
      result["field"]["1,1"]["moves"],
      [1, 2]
    )
  end

  test "returns adjacent enemy techniques as attack targets" do
    state = base_state

    state["field"][1][1] = technique(
      player_id: 1,
      attack_range: 1
    )

    state["field"][1][2] = technique(
      player_id: 2
    )

    result = GameEngine::AvailableActions.call(
      state: state,
      player_id: 1
    )

    assert_includes(
      result["field"]["1,1"]["attacks"],
      [1, 2]
    )
  end

  test "does not return friendly objects as attack targets" do
    state = base_state

    state["field"][1][1] = technique(
      player_id: 1,
      attack_range: 1
    )

    state["field"][1][2] = technique(
      player_id: 1
    )

    result = GameEngine::AvailableActions.call(
      state: state,
      player_id: 1
    )

    refute_includes(
      result["field"]["1,1"]["attacks"],
      [1, 2]
    )
  end

  test "does not return attacks for a technique that already attacked" do
    state = base_state

    state["field"][1][1] = technique(
      player_id: 1,
      has_attacked: true
    )

    state["field"][1][2] = technique(
      player_id: 2
    )

    result = GameEngine::AvailableActions.call(
      state: state,
      player_id: 1
    )

    assert_equal(
      [],
      result["field"]["1,1"]["attacks"]
    )
  end

  test "returns distant artillery attack when enemy target is spotted" do
    state = base_state

    state["field"][1][1] = technique(
      player_id: 1,
      technique_type: "artillery",
      attack_range: 1
    )

    state["field"][2][2] = technique(
      player_id: 1
    )

    state["field"][2][3] = technique(
      player_id: 2
    )

    result = GameEngine::AvailableActions.call(
      state: state,
      player_id: 1
    )

    assert_includes(
      result["field"]["1,1"]["attacks"],
      [2, 3]
    )
  end

  test "returns distant headquarters attack for artillery with spotting" do
    state = base_state

    state["field"][1][1] = technique(
      player_id: 1,
      technique_type: "artillery",
      attack_range: 1
    )

    state["field"][1][3] = technique(
      player_id: 1
    )

    state["field"][2][4] = headquarters(
      player_id: 2
    )

    result = GameEngine::AvailableActions.call(
      state: state,
      player_id: 1
    )

    assert_includes(
      result["field"]["1,1"]["attacks"],
      [2, 4]
    )
  end

  test "returns enemy headquarters as attack target from own headquarters" do
    state = base_state

    state["field"][0][4] = headquarters(
      player_id: 2
    )

    result = GameEngine::AvailableActions.call(
      state: state,
      player_id: 1
    )

    assert_includes(
      result["field"]["2,0"]["attacks"],
      [0, 4]
    )
  end

  test "returns empty moves for headquarters" do
    state = base_state

    result = GameEngine::AvailableActions.call(
      state: state,
      player_id: 1
    )

    assert_equal(
      [],
      result["field"]["2,0"]["moves"]
    )
  end

  test "returns available technique deployment positions" do
    state = base_state

    state["players"]["1"]["hand"] = [
      card(
        card_id: 101,
        card_type: "technique",
        price: 2
      )
    ]

    state["players"]["1"]["resources"] = 3

    result = GameEngine::AvailableActions.call(
      state: state,
      player_id: 1
    )

    assert_equal(
      {
        "type" => "technique",
        "drop_zone" => "field",
        "resources_sufficient" => true,
        "positions" => [
          [1, 0],
          [1, 1],
          [2, 1]
        ]
      },
      result["hand"]["101"]
    )
  end

  test "does not return technique deployment positions when resources are insufficient" do
    state = base_state

    state["players"]["1"]["hand"] = [
      card(
        card_id: 101,
        card_type: "technique",
        price: 4
      )
    ]

    state["players"]["1"]["resources"] = 3

    result = GameEngine::AvailableActions.call(
      state: state,
      player_id: 1
    )

    assert_equal(
      {
        "type" => "technique",
        "drop_zone" => "field",
        "resources_sufficient" => false,
        "positions" => []
      },
      result["hand"]["101"]
    )
  end

  test "resources are sufficient even when no technique deployment positions are available" do
    state = base_state

    state["players"]["1"]["hand"] = [
      card(
        card_id: 101,
        card_type: "technique",
        price: 2
      )
    ]

    state["players"]["1"]["resources"] = 3

    state["field"][1][0] = technique(player_id: 2)
    state["field"][1][1] = technique(player_id: 2)
    state["field"][2][1] = technique(player_id: 2)

    result = GameEngine::AvailableActions.call(
      state: state,
      player_id: 1
    )

    assert_equal(
      true,
      result["hand"]["101"]["resources_sufficient"]
    )

    assert_equal(
      [],
      result["hand"]["101"]["positions"]
    )
  end

  test "does not return occupied technique deployment positions" do
    state = base_state

    state["field"][1][1] = technique(
      player_id: 2
    )

    state["players"]["1"]["hand"] = [
      card(
        card_id: 101,
        card_type: "technique",
        price: 1
      )
    ]

    result = GameEngine::AvailableActions.call(
      state: state,
      player_id: 1
    )

    refute_includes(
      result["hand"]["101"]["positions"],
      [1, 1]
    )

    assert_equal(
      true,
      result["hand"]["101"]["resources_sufficient"]
    )
  end

  test "returns free platoon slots" do
    state = base_state

    state["players"]["1"]["platoons"] = [
      platoon(player_id: 1),
      nil,
      platoon(player_id: 1),
      nil
    ]

    state["players"]["1"]["hand"] = [
      card(
        card_id: 102,
        card_type: "platoon",
        price: 2
      )
    ]

    result = GameEngine::AvailableActions.call(
      state: state,
      player_id: 1
    )

    assert_equal(
      {
        "type" => "platoon",
        "drop_zone" => "platoon_bar",
        "resources_sufficient" => true,
        "slots" => [1, 3]
      },
      result["hand"]["102"]
    )
  end

  test "returns empty platoon slots when resources are insufficient" do
    state = base_state

    state["players"]["1"]["platoons"] = [
      nil,
      nil,
      nil,
      nil
    ]

    state["players"]["1"]["hand"] = [
      card(
        card_id: 102,
        card_type: "platoon",
        price: 5
      )
    ]

    state["players"]["1"]["resources"] = 2

    result = GameEngine::AvailableActions.call(
      state: state,
      player_id: 1
    )

    assert_equal(
      {
        "type" => "platoon",
        "drop_zone" => "platoon_bar",
        "resources_sufficient" => false,
        "slots" => []
      },
      result["hand"]["102"]
    )
  end

  test "resources are sufficient even when no platoon slots are available" do
    state = base_state

    state["players"]["1"]["platoons"] = [
      platoon(player_id: 1),
      platoon(player_id: 1),
      platoon(player_id: 1),
      platoon(player_id: 1)
    ]

    state["players"]["1"]["hand"] = [
      card(
        card_id: 102,
        card_type: "platoon",
        price: 2
      )
    ]

    state["players"]["1"]["resources"] = 3

    result = GameEngine::AvailableActions.call(
      state: state,
      player_id: 1
    )

    assert_equal(
      true,
      result["hand"]["102"]["resources_sufficient"]
    )

    assert_equal(
      [],
      result["hand"]["102"]["slots"]
    )
  end

  test "returns field drop zone for order without targeted ability" do
    state = base_state

    state["players"]["1"]["hand"] = [
      card(
        card_id: 103,
        card_type: "order",
        price: 1,
        abilities: [
          {
            "code" => "draw_cards"
          }
        ]
      )
    ]

    result = GameEngine::AvailableActions.call(
      state: state,
      player_id: 1
    )

    assert_equal(
      {
        "type" => "order",
        "drop_zone" => "field",
        "resources_sufficient" => true
      },
      result["hand"]["103"]
    )
  end

  test "returns enemy technique positions for damage technique order" do
    state = base_state

    state["field"][1][2] = technique(
      player_id: 2
    )

    state["field"][1][3] = headquarters(
      player_id: 2
    )

    state["players"]["1"]["hand"] = [
      card(
        card_id: 104,
        card_type: "order",
        price: 1,
        abilities: [
          {
            "code" => "damage_technique"
          }
        ]
      )
    ]

    result = GameEngine::AvailableActions.call(
      state: state,
      player_id: 1
    )

    assert_equal(
      {
        "type" => "order",
        "targets" => [[1, 2]],
        "resources_sufficient" => true
      },
      result["hand"]["104"]
    )
  end

  test "returns no order targets when resources are sufficient but no enemy techniques exist" do
    state = base_state

    state["players"]["1"]["hand"] = [
      card(
        card_id: 104,
        card_type: "order",
        price: 1,
        abilities: [
          {
            "code" => "damage_technique"
          }
        ]
      )
    ]

    state["players"]["1"]["resources"] = 3

    result = GameEngine::AvailableActions.call(
      state: state,
      player_id: 1
    )

    assert_equal(
      true,
      result["hand"]["104"]["resources_sufficient"]
    )

    assert_equal(
      [],
      result["hand"]["104"]["targets"]
    )
  end

  test "does not expose opponent hidden hand" do
    state = base_state

    state["players"]["2"]["hand"] = [
      card(
        card_id: 201,
        card_type: "technique"
      )
    ]

    result = GameEngine::AvailableActions.call(
      state: state,
      player_id: 1
    )

    assert_equal(
      {},
      result["hand"].except("201")
    )
  end

  test "does not modify original state" do
    state = base_state

    state["field"][1][1] = technique(
      player_id: 1
    )

    state["players"]["1"]["hand"] = [
      card(
        card_id: 101,
        card_type: "technique",
        price: 1
      )
    ]

    original_state = state.deep_dup

    GameEngine::AvailableActions.call(
      state: state,
      player_id: 1
    )

    assert_equal(
      original_state,
      state
    )
  end

  private

  def base_state
    {
      "status" => "started",
      "turn_number" => 1,
      "current_player_id" => "1",
      "turn_started_at" => Time.current,
      "players" => {
        "1" => {
          "nation_id" => 1,
          "hand" => [],
          "deck" => [],
          "graveyard" => [],
          "platoons" => [nil, nil, nil, nil],
          "resources" => 10,
          "remaining_time" => 600,
          "empty_deck_draw_attempts" => 0
        },
        "2" => {
          "nation_id" => 2,
          "hand" => [],
          "deck" => [],
          "graveyard" => [],
          "platoons" => [nil, nil, nil, nil],
          "resources" => 10,
          "remaining_time" => 600,
          "empty_deck_draw_attempts" => 0
        }
      },
      "field" => base_field,
      "result" => nil
    }
  end

  def base_field
    field = Array.new(
      GameEngine::GameState::FIELD_HEIGHT
    ) do
      Array.new(
        GameEngine::GameState::FIELD_WIDTH
      )
    end

    field[2][0] = headquarters(player_id: 1)
    field[0][4] = headquarters(player_id: 2)

    field
  end

  def technique(
    player_id:,
    technique_type: "light_tank",
    movement_type: "orthogonal",
    movement_count: 1,
    attack_range: 1,
    has_attacked: false
  )
    {
      "type" => "technique",
      "card_id" => 1,
      "player_id" => player_id,
      "nation_id" => player_id,
      "name" => "Test Technique",
      "technique_type" => technique_type,
      "hp" => 10,
      "firepower" => 3,
      "fuel" => 2,
      "attack_range" => attack_range,
      "movement_count" => movement_count,
      "movement_limit" => movement_count,
      "movement_type" => movement_type,
      "has_attacked" => has_attacked,
      "has_counterattacked" => false,
      "abilities" => []
    }
  end

  def headquarters(player_id:)
    {
      "type" => "headquarters",
      "card_id" => player_id * 10,
      "player_id" => player_id,
      "nation_id" => player_id,
      "name" => "Test HQ",
      "hp" => 20,
      "firepower" => 3,
      "fuel" => 5,
      "has_attacked" => false,
      "has_counterattacked" => false,
      "abilities" => []
    }
  end

  def platoon(player_id:)
    {
      "type" => "platoon",
      "card_id" => player_id * 100,
      "player_id" => player_id,
      "nation_id" => player_id,
      "name" => "Test Platoon",
      "hp" => 5,
      "firepower" => 2,
      "armor" => 2,
      "fuel" => 1
    }
  end

  def card(
    card_id:,
    card_type:,
    price: 1,
    abilities: []
  )
    {
      "card_id" => card_id,
      "name" => "Test Card",
      "nation_id" => 1,
      "card_type" => card_type,
      "weight" => 1,
      "price" => price,
      "abilities" => abilities
    }
  end
  
	test "returns empty result when game is finished" do
		state = base_state
		state["status"] = "finished"
		state["result"] = {
		  "winner_id" => "1",
		  "loser_id" => "2",
		  "reason" => "surrender"
		}

		state["players"]["1"]["hand"] = [
		  card(
		    card_id: 101,
		    card_type: "technique",
		    price: 1
		  )
		]

		result = GameEngine::AvailableActions.call(
		  state: state,
		  player_id: 1
		)

		assert_equal(
		  {
		    "field" => {},
		    "hand" => {}
		  },
		  result
		)
	end
end
