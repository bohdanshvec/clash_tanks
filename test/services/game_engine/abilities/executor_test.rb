require "test_helper"

class GameEngine::Abilities::ExecutorTest < ActiveSupport::TestCase
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
  end

  test "executes handler based on ability code" do
    ability = {
      "code" => "damage_technique",
      "damage" => 3
    }

    result = GameEngine::Abilities::Executor.new(
      state: @state,
      ability: ability,
      player_id: 42,
      targets: [{ row: 1, column: 2 }]
    ).call

    assert result.success?
    assert_equal 7, result.state["field"][1][2]["hp"]
  end

  test "passes ability parameters to handler" do
    ability = {
      "code" => "damage_technique",
      "damage" => 7
    }

    result = GameEngine::Abilities::Executor.new(
      state: @state,
      ability: ability,
      player_id: 42,
      targets: [{ row: 1, column: 2 }]
    ).call

    assert result.success?
    assert_equal 3, result.state["field"][1][2]["hp"]
  end

  test "returns failure for unknown ability" do
    ability = {
      "code" => "unknown_ability"
    }

    result = GameEngine::Abilities::Executor.new(
      state: @state,
      ability: ability,
      player_id: 42,
      targets: []
    ).call

    refute result.success?
    assert_equal "Unknown ability", result.error
  end

  test "does not modify original state" do
    ability = {
      "code" => "damage_technique",
      "damage" => 3
    }

    result = GameEngine::Abilities::Executor.new(
      state: @state,
      ability: ability,
      player_id: 42,
      targets: [{ row: 1, column: 2 }]
    ).call

    assert_equal 10, @state["field"][1][2]["hp"]
    assert_equal 7, result.state["field"][1][2]["hp"]
  end
end
