
require "test_helper"

class GameEngine::Attacks::HeadquartersCombatTest < ActiveSupport::TestCase
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

    @headquarters = @state["field"][0][4]
  end

  def add_defender(position:, hp:, player_id: OPPONENT_ID, ability: true, card_id: 100)
    row, column = position

    abilities = ability ? [
      { "code" => "headquarters_defender" }
    ] : []

    @state["field"][row][column] = {
      "type" => "technique",
      "card_id" => card_id,
      "player_id" => player_id,
      "name" => "Test Defender",
      "hp" => hp,
      "firepower" => 3,
      "abilities" => abilities
    }
  end

  def apply_damage(damage, events: nil)
    GameEngine::Attacks::HeadquartersCombat.apply_damage(
      state: @state,
      headquarters: @headquarters,
      damage: damage,
      events: events
    )
  end

  test "headquarters defender partially absorbs incoming damage" do
    add_defender(position: [0, 3], hp: 7)

    result = apply_damage(4)

    assert_equal 4, result[:technique_absorbed]
    assert_equal 0, result[:armor_absorbed]
    assert_equal 0, result[:headquarters_damage]

    assert_equal 3, @state["field"][0][3]["hp"]
    assert_equal 20, @headquarters["hp"]
  end

  test "damage passes from destroyed defender through platoon armor to headquarters" do
    add_defender(position: [0, 3], hp: 3)

    @state["players"][OPPONENT_ID.to_s]["platoons"][0] = {
      "type" => "platoon",
      "card_id" => 200,
      "player_id" => OPPONENT_ID,
      "name" => "Test Platoon",
      "hp" => 10,
      "armor" => 4,
      "firepower" => 2
    }

    events = []
    result = apply_damage(10, events: events)

    assert_equal 3, result[:technique_absorbed]
    assert_equal 4, result[:armor_absorbed]
    assert_equal 3, result[:headquarters_damage]

    assert_nil @state["field"][0][3]

    graveyard = @state["players"][OPPONENT_ID.to_s]["graveyard"]

    assert_equal 1, graveyard.size
    assert_equal 100, graveyard.first["card_id"]
    assert_equal 0, graveyard.first["hp"]

    platoon = @state["players"][OPPONENT_ID.to_s]["platoons"][0]

    assert_equal 6, platoon["hp"]
    assert_equal 17, @headquarters["hp"]

    assert_equal(
      %w[technique_damaged technique_destroyed platoon_damaged],
      events.map { |event| event[:type] }
    )
  end

  test "defender with highest hp absorbs damage before closer defender" do
    add_defender(position: [0, 3], hp: 6, card_id: 101)
    add_defender(position: [1, 3], hp: 8, card_id: 102)

    result = apply_damage(3)

    assert_equal 3, result[:technique_absorbed]

    assert_equal 6, @state["field"][0][3]["hp"]
    assert_equal 5, @state["field"][1][3]["hp"]
    assert_equal 20, @headquarters["hp"]
  end

  test "equal hp defenders are selected by distance and then coordinates" do
    add_defender(position: [0, 3], hp: 5, card_id: 101)
    add_defender(position: [1, 4], hp: 5, card_id: 102)
    add_defender(position: [1, 3], hp: 5, card_id: 103)

    result = apply_damage(6)

    assert_equal 6, result[:technique_absorbed]

    # [0, 3] is the first defender by distance and coordinates.
    assert_nil @state["field"][0][3]

    # [1, 4] is the next defender.
    assert_equal 4, @state["field"][1][4]["hp"]

    # [1, 3] is farther from headquarters and remains untouched.
    assert_equal 5, @state["field"][1][3]["hp"]

    graveyard = @state["players"][OPPONENT_ID.to_s]["graveyard"]

    assert_equal [101], graveyard.map { |card| card["card_id"] }
  end

  test "enemy, distant and non-defender techniques do not protect headquarters" do
    add_defender(
      position: [0, 3],
      hp: 10,
      ability: false,
      card_id: 101
    )

    add_defender(
      position: [1, 4],
      hp: 10,
      player_id: PLAYER_ID,
      card_id: 102
    )

    add_defender(
      position: [2, 4],
      hp: 10,
      card_id: 103
    )

    result = apply_damage(4)

    assert_equal 0, result[:technique_absorbed]
    assert_equal 4, result[:headquarters_damage]

    assert_equal 10, @state["field"][0][3]["hp"]
    assert_equal 10, @state["field"][1][4]["hp"]
    assert_equal 10, @state["field"][2][4]["hp"]

    assert_equal 16, @headquarters["hp"]
  end

  test "zero or negative damage does not affect defenders, platoons or headquarters" do
    add_defender(position: [0, 3], hp: 7)

    @state["players"][OPPONENT_ID.to_s]["platoons"][0] = {
      "type" => "platoon",
      "card_id" => 200,
      "player_id" => OPPONENT_ID,
      "hp" => 10,
      "armor" => 4,
      "firepower" => 2
    }

    [0, -3].each do |damage|
      result = apply_damage(damage)

      assert_equal 0, result[:technique_absorbed]
      assert_equal 0, result[:armor_absorbed]
      assert_equal 0, result[:headquarters_damage]
    end

    assert_equal 7, @state["field"][0][3]["hp"]
    assert_equal 10, @state["players"][OPPONENT_ID.to_s]["platoons"][0]["hp"]
    assert_equal 20, @headquarters["hp"]
  end
end
