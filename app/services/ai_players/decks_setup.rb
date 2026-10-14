module AiPlayers
  class DecksSetup
    DECKS = [
      {
        name: "ИИ — США: лёгкая техника",
        nation_code: "usa",
        headquarters_code: "usa_headquarters_second_front",
        card_codes: {
          "usa_m3_stuart" => 3,
          "usa_m8_greyhound" => 2,
          "usa_m24_chaffee" => 2,
          "usa_m4_sherman" => 1,
          "usa_lend_liz" => 1,
          "usa_ognevoj_nalyot" => 1
        }
      },
      {
        name: "ИИ — СССР: средняя техника",
        nation_code: "ussr",
        headquarters_code: "ussr_headquarters_west_front",
        card_codes: {
          "ussr_t_34" => 3,
          "ussr_t_34_85" => 2,
          "ussr_is_2" => 1,
          "ussr_t_70" => 1,
          "ussr_zalp_katyushi" => 1,
          "ussr_popolnenie" => 1,
          "ussr_strelkovyj_vzvod" => 1
        }
      },
      {
        name: "ИИ — Германия: тяжёлая техника",
        nation_code: "germany",
        headquarters_code: "germany_headquarters_operation_weiß",
        card_codes: {
          "germany_tiger_i" => 2,
          "germany_jagdpanther" => 3,
          "germany_pz_iv_h" => 1,
          "germany_hummel" => 1,
          "germany_tocnyj_vystrel" => 1,
          "germany_radioperekhvat" => 1,
          "germany_grenaderskij_vzvod" => 1
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
