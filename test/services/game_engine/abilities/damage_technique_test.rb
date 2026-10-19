require "test_helper"

class GameEngine::Abilities::DamageTechniqueTest < ActiveSupport::TestCase
  setup do
    @state = GameEngine::GameState.initial(
      current_player_id: 42,
      participants: [
        headquarters_participant(player_id: 42, nation_id: 10),
        headquarters_participant(player_id: 57, nation_id: 20)
      ]
    )

    @state["field"][1][2] = {
      "type" => "technique",
      "card_id" => 15,
      "player_id" => 57,
      "nation_id" => 20,
      "name" => "Т-34",
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

    @ability = {
      "code" => "damage_technique",
      "damage" => 3
    }
  end

  test "damages enemy technique and emits damage event" do
    result = execute_ability

    assert result.success?
    assert_equal 7, result.state["field"][1][2]["hp"]

    assert_equal(
      [
        {
          type: "damage_applied",
          source: {
            type: "order",
            code: "damage_technique"
          },
          target: {
            type: "technique",
            player_id: 57,
            card_id: 15,
            name: "Т-34",
            position: [1, 2]
          },
          damage: 3,
          hp_before: 10,
          hp_after: 7
        }
      ],
      result.events
    )
  end

  test "does not modify original state" do
    result = execute_ability

    assert_equal 10, @state["field"][1][2]["hp"]
    refute_same @state, result.state
  end

  test "destroys technique when hp reaches zero and emits events in order" do
    @state["field"][1][2]["hp"] = 3

    result = execute_ability

    assert result.success?
    assert_nil result.state["field"][1][2]

    graveyard = result.state["players"]["57"]["graveyard"]

    assert_equal 1, graveyard.size
    assert_equal 15, graveyard.first["card_id"]
    assert_equal 0, graveyard.first["hp"]

		assert_equal(
			%w[damage_applied technique_destroyed],
			result.events.map { |event| event[:type] }
		)

    assert_equal 3, result.events.first[:hp_before]
    assert_equal 0, result.events.first[:hp_after]
    assert_equal 3, result.events.first[:damage]

    assert_equal(
      {
        type: "technique",
        player_id: 57,
        card_id: 15,
        name: "Т-34",
        position: [1, 2]
      },
      result.events.first[:target]
    )

    assert_equal(
      result.events.first[:target],
      result.events.last[:target]
    )

    assert_equal(
      {
        type: "order",
        code: "damage_technique"
      },
      result.events.last[:source]
    )
  end

  test "clamps overkill damage to zero hp" do
    @state["field"][1][2]["hp"] = 2
    @ability["damage"] = 10

    result = execute_ability

    assert result.success?
    assert_nil result.state["field"][1][2]

    event = result.events.find { |item| item[:type] == "damage_applied" }

    assert_equal 2, event[:damage]
    assert_equal 2, event[:hp_before]
    assert_equal 0, event[:hp_after]
  end

  test "does not damage own technique" do
    @state["field"][1][2]["player_id"] = 42

    result = execute_ability

    refute result.success?
    assert_equal "Invalid target", result.error
    assert_equal 10, @state["field"][1][2]["hp"]
  end

  test "rejects non technique target" do
    @state["field"][1][2] = {
      "type" => "headquarters",
      "player_id" => 57,
      "nation_id" => 20
    }

    result = execute_ability

    refute result.success?
    assert_equal "Invalid target", result.error
  end

  test "rejects invalid target coordinates" do
    result = GameEngine::Abilities::DamageTechnique.new(
      state: @state,
      ability: @ability,
      player_id: 42,
      targets: [{ row: 3, column: 2 }]
    ).call

    refute result.success?
    assert_equal "Invalid target", result.error
  end

  private

  def execute_ability
    GameEngine::Abilities::DamageTechnique.new(
      state: @state,
      ability: @ability,
      player_id: 42,
      targets: [{ row: 1, column: 2 }]
    ).call
  end
end
