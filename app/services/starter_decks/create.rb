module StarterDecks
  class Create
    STARTER_DECKS = [
      {
        name: "Operation „Weiß“",
        headquarters_code: "germany_headquarters_operation_weiß",
        card_codes: %w[
        	germany_sd_222
        	germany_pz_iii_ausf
        	germany_pz_iv_ausf
        	germany_hetzer
        	germany_jagdpanther_iv
        	germany_jagdpanther
        	germany_tiger_i
        	germany_sturmpanzer_iv
        	germany_postril
        	germany_grenaderi
        ]
      },
      {
        name: "Second front",
        headquarters_code: "usa_headquarters_second_front",
        card_codes: %w[
        	usa_m8_greyhound
        	usa_m3_lee_grant
        	usa_m4_sherman
        	usa_m4a3e8
        	usa_m4a3e2
        	usa_m10_wolverine
        	usa_m26_pershing
        	usa_m8_hmc_scott
        	usa_vognevij_nalit
        	usa_inzheneri        
        ]
      },
      {
        name: "Західний фронт",
        headquarters_code: "ussr_headquarters_west_front",
        card_codes: %w[
          ussr_t_60
          ussr_t_34
          ussr_t_34_76
          ussr_su_85
          ussr_su_100
          ussr_t_35
          ussr_kv_1
          ussr_su_76m
          ussr_zalp_katyushi
          ussr_strilci
        ]
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

      definition[:card_codes].each do |code|
        card = Card.find_by!(code: code)

        deck.deck_cards.create!(
          card: card,
          quantity: 1
        )
      end

      deck
    end
  end
end
