module AiPlayers
  class DecksSetup
    DECKS = [
      {
        name: "АІ — США: важка техніка",
        nation_code: "usa",
        headquarters_code: "usa_headquarters_second_front",
        card_codes: {
          "usa_m4_sherman" => 1,
          "usa_m4a3e2_jumbo" => 3,
          "usa_m10_wolverine" => 3,
          "usa_m26_pershing" => 3
        }
      },
      {
        name: "АІ — СРСР: легка техніка",
        nation_code: "ussr",
        headquarters_code: "ussr_headquarters_west_front",
        card_codes: {
          "ussr_t_34" => 3,
          "ussr_t_34_76" => 3,
          "ussr_su_85" => 3,
          "ussr_kv_1" => 1
        }
      },
      {
        name: "АІ — Германія: середня техніка",
        nation_code: "germany",
        headquarters_code: "germany_headquarters_operation_weiß",
        card_codes: {
          "germany_tiger_i" => 2,
          "germany_jagdpanther" => 1,
          "germany_jagdpanther_iv" => 1,
          "germany_jagdpanther_38a_hetzer" => 2,
          "germany_pz_iv_a_f1" => 3,
          "germany_tocnyj_postil" => 1
        }
      }
    ].freeze

    def self.call
      new.call
    end

    def call
      player = AiPlayers::Setup.call

      Deck.transaction do
        DECKS.map do |definition|
          find_or_create_deck(player, definition)
        end
      end
    end

    private

    def find_or_create_deck(player, definition)
      existing_deck = Deck.find_by(
        player: player,
        name: definition[:name]
      )

      return existing_deck if existing_deck

      nation = Nation.find_by!(code: definition[:nation_code])

      headquarters_card = Card.find_by!(
        code: definition[:headquarters_code]
      )

      deck = Deck.create!(
        player: player,
        name: definition[:name],
        nation: nation,
        headquarters_card: headquarters_card
      )

      definition[:card_codes].each do |code, quantity|
        card = Card.find_by!(code: code)

        deck.deck_cards.create!(
          card: card,
          quantity: quantity
        )
      end

      deck
    end
  end
end
