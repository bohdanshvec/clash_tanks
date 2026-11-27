module StarterDecks
  class Create
    STARTER_DECKS = [
      {
        name: "Operation „Weiß“",
        headquarters_code: "germany_headquarters_operation_weiß",
        card_codes: {
          "germany_sd_222" => 1,
          "germany_pz_iii_ausf" => 1,
          "germany_pz_iv_ausf" => 2,
          "germany_hetzer" => 2,
          "germany_jagdpanther_iv" => 2,
          "germany_jagdpanther" => 1,
          "germany_tiger_i" => 2,
          "germany_sturmpanzer_iv" => 1,
          "germany_postril" => 2,
          "germany_grenaderi" => 1
        }
      },
      {
        name: "Second front",
        headquarters_code: "usa_headquarters_second_front",
        card_codes: {
          "usa_m8_greyhound" => 1,
          "usa_m4_sherman" => 2,
          "usa_m4a3e8" => 2,
          "usa_m4a3e2" => 2,
          "usa_m10_wolverine" => 2,
          "usa_m26_pershing" => 2,
          "usa_m8_hmc_scott" => 1,
          "usa_vognevij_nalit" => 1,
          "usa_inzheneri" => 2
        }
      },
      {
        name: "Західний фронт",
        headquarters_code: "ussr_headquarters_west_front",
        card_codes: {
          "ussr_t_60" => 1,
          "ussr_t_34" => 2,
          "ussr_t_34_76" => 2,
          "ussr_su_85" => 2,
          "ussr_su_100" => 1,
          "ussr_t_35" => 1,
          "ussr_kv_1" => 2,
          "ussr_su_76m" => 1,
          "ussr_zalp_katyushi" => 2,
          "ussr_strilci" => 1
        }
      }
    ].freeze

    def self.call(player)
      new(player).call
    end

    def initialize(player)
      @player = player
    end

    def call
      STARTER_DECKS.map do |definition|
        create_deck(definition)
      end
    end

    private

    attr_reader :player

    def create_deck(definition)
      headquarters_card = Card.find_by!(
        code: definition[:headquarters_code]
      )

      deck = player.decks.create!(
        name: definition[:name],
        nation: headquarters_card.nation,
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
