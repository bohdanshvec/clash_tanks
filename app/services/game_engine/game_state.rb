module GameEngine
  class GameState
    FIELD_HEIGHT = 3
    FIELD_WIDTH = 5

    def self.initial(current_player_id:, player_ids:)
      {
        "turn_number" => 1,
        "current_player_id" => current_player_id,
        "players" => initial_players(player_ids),
        "field" => empty_field
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

    def self.empty_field
      Array.new(FIELD_HEIGHT) { Array.new(FIELD_WIDTH) }
    end
  end
end
