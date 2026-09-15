require "test_helper"

class GameEngine::Resources::FuelCalculatorTest < ActiveSupport::TestCase
  test "calculates fuel from headquarters" do
    state = state_with(
      headquarters_fuel: 5
    )

    fuel = calculate(state, player_id: 1)

    assert_equal 5, fuel
  end

  test "calculates fuel from headquarters and techniques" do
    state = state_with(
      headquarters_fuel: 5,
      techniques: [
        technique(player_id: 1, fuel: 2),
        technique(player_id: 1, fuel: 1)
      ]
    )

    fuel = calculate(state, player_id: 1)

    assert_equal 8, fuel
  end

  test "calculates fuel from headquarters, techniques and platoons" do
    state = state_with(
      headquarters_fuel: 5,
      techniques: [
        technique(player_id: 1, fuel: 2),
        technique(player_id: 1, fuel: 1)
      ],
      platoons: [
        platoon(fuel: 3),
        platoon(fuel: 2),
        nil,
        nil
      ]
    )

    fuel = calculate(state, player_id: 1)

    assert_equal 13, fuel
  end

  test "does not count opponent headquarters and techniques" do
    state = state_with(
      headquarters_fuel: 5,
      opponent_headquarters_fuel: 10,
      techniques: [
        technique(player_id: 1, fuel: 2),
        technique(player_id: 2, fuel: 7)
      ]
    )

    fuel = calculate(state, player_id: 1)

    assert_equal 7, fuel
  end

  test "ignores empty platoon slots" do
    state = state_with(
      headquarters_fuel: 5,
      platoons: [
        platoon(fuel: 3),
        nil,
        platoon(fuel: 2),
        nil
      ]
    )

    fuel = calculate(state, player_id: 1)

    assert_equal 10, fuel
  end

  test "does not modify state" do
    state = state_with(
      headquarters_fuel: 5,
      techniques: [
        technique(player_id: 1, fuel: 2)
      ],
      platoons: [
        platoon(fuel: 3),
        nil,
        nil,
        nil
      ]
    )
    original_state = state.deep_dup

    calculate(state, player_id: 1)

    assert_equal original_state, state
  end

  private

  def calculate(state, player_id:)
    GameEngine::Resources::FuelCalculator.call(
      state: state,
      player_id: player_id
    )
  end

  def state_with(
    headquarters_fuel: 5,
    opponent_headquarters_fuel: 5,
    techniques: [],
    platoons: [nil, nil, nil, nil]
  )
    {
      "players" => {
        "1" => {
          "nation_id" => 1,
          "hand" => [],
          "deck" => [],
          "graveyard" => [],
          "platoons" => platoons,
          "resources" => 0,
          "remaining_time" => 600
        },
        "2" => {
          "nation_id" => 2,
          "hand" => [],
          "deck" => [],
          "graveyard" => [],
          "platoons" => [nil, nil, nil, nil],
          "resources" => 0,
          "remaining_time" => 600
        }
      },
      "field" => [
        [nil, nil, nil, nil, opponent_headquarters(player_id: 2, fuel: opponent_headquarters_fuel)],
        [nil, *techniques, nil, nil, nil],
        [headquarters(player_id: 1, fuel: headquarters_fuel), nil, nil, nil, nil]
      ]
    }
  end

  def headquarters(player_id:, fuel:)
    {
      "type" => "headquarters",
      "card_id" => player_id,
      "player_id" => player_id,
      "nation_id" => player_id,
      "name" => "HQ",
      "hp" => 20,
      "firepower" => 3,
      "fuel" => fuel,
      "abilities" => []
    }
  end

  def opponent_headquarters(player_id:, fuel:)
    headquarters(player_id:, fuel:)
  end

  def technique(player_id:, fuel:)
    {
      "type" => "technique",
      "card_id" => 100 + player_id,
      "player_id" => player_id,
      "nation_id" => player_id,
      "name" => "Technique",
      "technique_type" => "medium_tank",
      "hp" => 10,
      "firepower" => 4,
      "fuel" => fuel,
      "attack_range" => 1,
      "movement_count" => 1,
      "movement_type" => "diagonal",
      "has_attacked" => false,
      "has_counterattacked" => false
    }
  end

  def platoon(fuel:)
    {
      "type" => "platoon",
      "card_id" => 200,
      "player_id" => 1,
      "nation_id" => 1,
      "name" => "Platoon",
      "firepower" => 5,
      "hp" => 10,
      "armor" => 3,
      "fuel" => fuel
    }
  end
end
