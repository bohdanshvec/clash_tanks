module GameEngine
  class GameState
    FIELD_HEIGHT = 3
    FIELD_WIDTH = 5

    HEADQUARTERS_POSITIONS = [
      { row: 2, column: 0 },
      { row: 0, column: 4 }
    ].freeze

    def self.initial(current_player_id:, player_ids:)
      {
        "turn_number" => 1,
        "current_player_id" => current_player_id,
        "players" => initial_players(player_ids),
        "field" => initial_field(player_ids)
      }
    end

    def self.initial_players(player_ids)
      player_ids.to_h do |player_id|
        [
          player_id.to_s,
          {
            "hand" => [],
            "resources" => 0,
            "remaining_time" => nil
          }
        ]
      end
    end

    def self.initial_field(player_ids)
      field = empty_field

      player_ids.each_with_index do |player_id, index|
        position = HEADQUARTERS_POSITIONS[index]

        field[position[:row]][position[:column]] = {
          "type" => "headquarters",
          "player_id" => player_id
        }
      end

      field
    end

    def self.empty_field
      Array.new(FIELD_HEIGHT) { Array.new(FIELD_WIDTH) }
    end

    def self.valid_coordinates?(row:, column:)
      row.between?(0, FIELD_HEIGHT - 1) &&
        column.between?(0, FIELD_WIDTH - 1)
    end

    def self.object_at(field:, row:, column:)
      raise ArgumentError, "Invalid coordinates" unless valid_coordinates?(row:, column:)

      field[row][column]
    end

    def self.place_object(field:, object:, row:, column:)
      raise ArgumentError, "Invalid coordinates" unless valid_coordinates?(row:, column:)
      raise ArgumentError, "Cell is occupied" unless field[row][column].nil?

      new_field = field.map(&:dup)
      new_field[row][column] = object

      new_field
    end

    def self.move_object(field:, from_row:, from_column:, to_row:, to_column:)
      raise ArgumentError, "Invalid source coordinates" unless valid_coordinates?(
        row: from_row,
        column: from_column
      )

      raise ArgumentError, "Invalid destination coordinates" unless valid_coordinates?(
        row: to_row,
        column: to_column
      )

      object = field[from_row][from_column]

      raise ArgumentError, "Source cell is empty" if object.nil?
      raise ArgumentError, "Headquarters cannot be moved" if object["type"] == "headquarters"
      raise ArgumentError, "Destination cell is occupied" unless field[to_row][to_column].nil?

      raise ArgumentError, "Cannot move onto headquarters" if headquarters_at?(
        field:,
        row: to_row,
        column: to_column
      )

      new_field = field.map(&:dup)
      new_field[from_row][from_column] = nil
      new_field[to_row][to_column] = object

      new_field
    end

    def self.headquarters_at?(field:, row:, column:)
      object = field[row][column]

      object && object["type"] == "headquarters"
    end
  end
end
