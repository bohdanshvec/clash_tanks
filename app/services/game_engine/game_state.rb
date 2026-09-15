module GameEngine
  class GameState
    FIELD_HEIGHT = 3
    FIELD_WIDTH = 5
    TURN_TIME = 10.minutes.to_i

    HEADQUARTERS_POSITIONS = [
      { row: 2, column: 0 },
      { row: 0, column: 4 }
    ].freeze

    def self.initial(current_player_id:, participants:)
      {
        "turn_number" => 1,
        "current_player_id" => current_player_id,
        "turn_started_at" => Time.current.change(usec: 0).iso8601,
        "players" => initial_players(participants),
        "field" => initial_field(participants)
      }
    end

    def self.cards_from_deck(deck)
      deck.deck_cards.includes(
        card: [:technique, :platoon, { card_abilities: :ability }]
      ).flat_map do |deck_card|
        Array.new(deck_card.quantity) do
          card = deck_card.card
          card_data = {
            "card_id" => card.id,
            "name" => card.name,
            "card_type" => card.card_type,
            "nation_id" => card.nation_id,
            "weight" => card.weight,
            "price" => card.price
          }

          if card.technique
            card_data["technique"] = {
              "technique_type" => card.technique.technique_type,
              "attack_range" => card.technique.attack_range,
              "movement_count" => card.technique.movement_count,
              "movement_type" => card.technique.movement_type,
              "firepower" => card.technique.firepower,
              "hp" => card.technique.hp,
              "fuel" => card.technique.fuel
            }
          end

          if card.platoon
            card_data["platoon"] = {
              "firepower" => card.platoon.firepower,
              "hp" => card.platoon.hp,
              "armor" => card.platoon.armor,
              "fuel" => card.platoon.fuel
            }
          end

          if card.card_abilities.any?
            card_data["abilities"] = card.card_abilities.map do |card_ability|
              { "code" => card_ability.ability.code }.merge(card_ability.parameters)
            end
          end

          card_data
        end
      end
    end

    def self.initial_players(participants)
      participants.to_h do |participant|
        player_id = participant[:player_id]
        nation_id = participant[:nation_id]

        [
          player_id.to_s,
          {
            "nation_id" => nation_id,
            "hand" => participant[:hand] || [],
            "deck" => participant[:deck] || [],
            "graveyard" => [],
            "platoons" => [nil, nil, nil, nil],
            "resources" => 0,
            "remaining_time" => TURN_TIME
          }
        ]
      end
    end

    def self.initial_field(participants)
      field = empty_field

      participants.each_with_index do |participant, index|
        position = HEADQUARTERS_POSITIONS[index]

        field[position[:row]][position[:column]] = {
          "type" => "headquarters",
          "player_id" => participant[:player_id],
          "nation_id" => participant[:nation_id]
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
      raise ArgumentError, "Invalid source coordinates" unless valid_coordinates?(row: from_row, column: from_column)
      raise ArgumentError, "Invalid destination coordinates" unless valid_coordinates?(row: to_row, column: to_column)

      object = field[from_row][from_column]

      raise ArgumentError, "Source cell is empty" if object.nil?
      raise ArgumentError, "Headquarters cannot be moved" if object["type"] == "headquarters"
      raise ArgumentError, "Destination cell is occupied" unless field[to_row][to_column].nil?
      raise ArgumentError, "Cannot move onto headquarters" if headquarters_at?(field:, row: to_row, column: to_column)

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
