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

    def create_player(email: nil, name: nil, password: "password")
      email ||= "player#{Player.maximum(:id).to_i + 1}@example.com"

      Player.create!(
        email: email,
        name: name,
        password: password
      )
    end

    def create_headquarters_card(nation:, name: "Test HQ")
      card = Card.create!(
        code: "#{nation.code}_#{name.parameterize(separator: "_")}_#{SecureRandom.hex(4)}",
        nation: nation,
        name: name,
        card_type: "headquarters",
        weight: 1,
        price: nil
      )

      Headquarters.create!(
        card: card,
        hp: 20,
        firepower: 3,
        fuel: 5
      )

      card
    end
    
		def create_complete_deck(player:, name: "Test Deck")
			nation = Nation.create!(
				name: "Test Nation #{SecureRandom.hex(4)}",
				code: "test_#{SecureRandom.hex(4)}"
			)

			headquarters_card = create_headquarters_card(nation: nation)

			deck = Deck.create!(
				player: player,
				nation: nation,
				name: name,
				headquarters_card: headquarters_card
			)

			10.times do |index|
				card = Card.create!(
				  code: "#{nation.code}_card_#{index}_#{SecureRandom.hex(4)}",
				  nation: nation,
				  name: "Test Card #{index}",
				  card_type: "order",
				  weight: 1,
				  price: 1
				)

				DeckCard.create!(
				  deck: deck,
				  card: card,
				  quantity: 1
				)
			end

			deck
		end

    def create_deck(player:, nation:, name: "Test Deck", headquarters_card: nil)
      headquarters_card ||= create_headquarters_card(nation: nation)

      Deck.create!(
        player: player,
        nation: nation,
        name: name,
        headquarters_card: headquarters_card
      )
    end
  end
end
