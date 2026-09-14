require "test_helper"

class GameEngine::Abilities::DamageTechniqueTest < ActiveSupport::TestCase
  PARTICIPANTS = [
    { player_id: 42, nation_id: 10 },
    { player_id: 57, nation_id: 20 }
  ].freeze

  setup do
    @state = GameEngine::GameState.initial(
      current_player_id: 42,
      participants: PARTICIPANTS
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

  test "damages enemy technique" do
    result = GameEngine::Abilities::DamageTechnique.new(
      state: @state,
      ability: @ability,
      player_id: 42,
      targets: [{ row: 1, column: 2 }]
    ).call

    assert result.success?
    assert_equal 7, result.state["field"][1][2]["hp"]
  end

  test "does not modify original state" do
    result = GameEngine::Abilities::DamageTechnique.new(
      state: @state,
      ability: @ability,
      player_id: 42,
      targets: [{ row: 1, column: 2 }]
    ).call

    assert_equal 10, @state["field"][1][2]["hp"]
    refute_same @state, result.state
  end

  test "destroys technique when hp reaches zero" do
    @state["field"][1][2]["hp"] = 3

    result = GameEngine::Abilities::DamageTechnique.new(
      state: @state,
      ability: @ability,
      player_id: 42,
      targets: [{ row: 1, column: 2 }]
    ).call

    assert result.success?
    assert_nil result.state["field"][1][2]

    assert_equal 1, result.state["players"]["57"]["graveyard"].size
    assert_equal(
      15,
      result.state["players"]["57"]["graveyard"].first["card_id"]
    )
  end

  test "does not damage own technique" do
    @state["field"][1][2]["player_id"] = 42

    result = GameEngine::Abilities::DamageTechnique.new(
      state: @state,
      ability: @ability,
      player_id: 42,
      targets: [{ row: 1, column: 2 }]
    ).call

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

    result = GameEngine::Abilities::DamageTechnique.new(
      state: @state,
      ability: @ability,
      player_id: 42,
      targets: [{ row: 1, column: 2 }]
    ).call

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
end
