require "test_helper"

class GameEngine::GameStateTest < ActiveSupport::TestCase
  test "initial returns the default game state" do
    state = GameEngine::GameState.initial(
      current_player_id: 42,
      player_ids: [42, 57]
    )

    assert_equal 1, state["turn_number"]
    assert_equal 42, state["current_player_id"]

    assert_equal(
      {
        "42" => {
          "hand" => [],
          "resources" => 0,
          "remaining_time" => nil
        },
        "57" => {
          "hand" => [],
          "resources" => 0,
          "remaining_time" => nil
        }
      },
      state["players"]
    )

    assert_equal(
      {
        "type" => "headquarters",
        "player_id" => 42
      },
      state["field"][2][0]
    )

    assert_equal(
      {
        "type" => "headquarters",
        "player_id" => 57
      },
      state["field"][0][4]
    )

    assert_equal 3, state["field"].size
    assert state["field"].all? { |row| row.size == 5 }

    assert_nil state["field"][0][0]
    assert_nil state["field"][0][3]
    assert_nil state["field"][1][0]
    assert_nil state["field"][1][4]
    assert_nil state["field"][2][1]
    assert_nil state["field"][2][4]
  end

  test "validates field coordinates" do
    assert GameEngine::GameState.valid_coordinates?(row: 0, column: 0)
    assert GameEngine::GameState.valid_coordinates?(row: 2, column: 4)

    refute GameEngine::GameState.valid_coordinates?(row: -1, column: 0)
    refute GameEngine::GameState.valid_coordinates?(row: 0, column: -1)
    refute GameEngine::GameState.valid_coordinates?(row: 3, column: 0)
    refute GameEngine::GameState.valid_coordinates?(row: 0, column: 5)
  end

  test "returns object at field coordinates" do
    field = GameEngine::GameState.initial_field([42, 57])

    assert_equal(
      {
        "type" => "headquarters",
        "player_id" => 42
      },
      GameEngine::GameState.object_at(field:, row: 2, column: 0)
    )

    assert_nil(
      GameEngine::GameState.object_at(field:, row: 1, column: 2)
    )
  end

  test "raises error for invalid coordinates when reading field" do
    field = GameEngine::GameState.empty_field

    assert_raises(ArgumentError, "Invalid coordinates") do
      GameEngine::GameState.object_at(field:, row: 3, column: 0)
    end
  end

  test "places object without changing original field" do
    field = GameEngine::GameState.empty_field

    object = {
      "type" => "technique",
      "id" => 1,
      "player_id" => 42
    }

    new_field = GameEngine::GameState.place_object(
      field:,
      object:,
      row: 1,
      column: 2
    )

    assert_nil field[1][2]
    assert_equal object, new_field[1][2]

    refute_same field, new_field
    refute_same field[1], new_field[1]
  end

  test "does not place object on occupied cell" do
    field = GameEngine::GameState.initial_field([42, 57])

    object = {
      "type" => "technique",
      "id" => 1,
      "player_id" => 42
    }

    assert_raises(ArgumentError, "Cell is occupied") do
      GameEngine::GameState.place_object(
        field:,
        object:,
        row: 2,
        column: 0
      )
    end
  end

  test "raises error for invalid coordinates when placing object" do
    field = GameEngine::GameState.empty_field

    object = {
      "type" => "technique",
      "id" => 1,
      "player_id" => 42
    }

    assert_raises(ArgumentError, "Invalid coordinates") do
      GameEngine::GameState.place_object(
        field:,
        object:,
        row: 3,
        column: 0
      )
    end
  end

  test "moves object to another cell" do
    field = GameEngine::GameState.empty_field

    object = {
      "type" => "technique",
      "id" => 1,
      "player_id" => 42
    }

    field = GameEngine::GameState.place_object(
      field:,
      object:,
      row: 1,
      column: 2
    )

    new_field = GameEngine::GameState.move_object(
      field:,
      from_row: 1,
      from_column: 2,
      to_row: 1,
      to_column: 3
    )

    assert_equal object, field[1][2]
    assert_nil field[1][3]

    assert_nil new_field[1][2]
    assert_equal object, new_field[1][3]
  end

  test "allows moving object diagonally" do
    field = GameEngine::GameState.empty_field

    object = {
      "type" => "technique",
      "id" => 1,
      "player_id" => 42
    }

    field = GameEngine::GameState.place_object(
      field:,
      object:,
      row: 1,
      column: 1
    )

    new_field = GameEngine::GameState.move_object(
      field:,
      from_row: 1,
      from_column: 1,
      to_row: 0,
      to_column: 2
    )

    assert_equal object, field[1][1]
    assert_nil field[0][2]

    assert_nil new_field[1][1]
    assert_equal object, new_field[0][2]
  end

  test "does not move object from an empty cell" do
    field = GameEngine::GameState.empty_field

    assert_raises(ArgumentError, "Source cell is empty") do
      GameEngine::GameState.move_object(
        field:,
        from_row: 1,
        from_column: 1,
        to_row: 1,
        to_column: 2
      )
    end
  end

  test "does not move object to an occupied cell" do
    field = GameEngine::GameState.empty_field

    object1 = {
      "type" => "technique",
      "id" => 1,
      "player_id" => 42
    }

    object2 = {
      "type" => "technique",
      "id" => 2,
      "player_id" => 42
    }

    field = GameEngine::GameState.place_object(
      field:,
      object: object1,
      row: 1,
      column: 1
    )

    field = GameEngine::GameState.place_object(
      field:,
      object: object2,
      row: 1,
      column: 2
    )

    assert_raises(ArgumentError, "Destination cell is occupied") do
      GameEngine::GameState.move_object(
        field:,
        from_row: 1,
        from_column: 1,
        to_row: 1,
        to_column: 2
      )
    end
  end

  test "does not move headquarters" do
    field = GameEngine::GameState.initial_field([42, 57])

    assert_raises(ArgumentError, "Headquarters cannot be moved") do
      GameEngine::GameState.move_object(
        field:,
        from_row: 2,
        from_column: 0,
        to_row: 1,
        to_column: 0
      )
    end
  end

  test "does not move object onto headquarters" do
    field = GameEngine::GameState.initial_field([42, 57])

    object = {
      "type" => "technique",
      "id" => 1,
      "player_id" => 42
    }

    field = GameEngine::GameState.place_object(
      field:,
      object:,
      row: 1,
      column: 0
    )

    assert_raises(ArgumentError, "Destination cell is occupied") do
      GameEngine::GameState.move_object(
        field:,
        from_row: 1,
        from_column: 0,
        to_row: 2,
        to_column: 0
      )
    end
  end

  test "raises error for invalid source coordinates when moving object" do
    field = GameEngine::GameState.empty_field

    assert_raises(ArgumentError, "Invalid source coordinates") do
      GameEngine::GameState.move_object(
        field:,
        from_row: -1,
        from_column: 0,
        to_row: 0,
        to_column: 0
      )
    end
  end

  test "raises error for invalid destination coordinates when moving object" do
    field = GameEngine::GameState.empty_field

    assert_raises(ArgumentError, "Invalid destination coordinates") do
      GameEngine::GameState.move_object(
        field:,
        from_row: 0,
        from_column: 0,
        to_row: 3,
        to_column: 0
      )
    end
  end
end
