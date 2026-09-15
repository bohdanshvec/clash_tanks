ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    def headquarters_participant(player_id:, nation_id:)
      {
        player_id: player_id,
        nation_id: nation_id,
        headquarters: {
          "type" => "headquarters",
          "card_id" => player_id,
          "player_id" => player_id,
          "nation_id" => nation_id,
          "name" => "Test HQ",
          "hp" => 20,
          "firepower" => 3,
          "fuel" => 5,
          "abilities" => []
        }
      }
    end
  end
end
