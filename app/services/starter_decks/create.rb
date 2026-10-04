module StarterDecks
  class Create
    STARTER_DECKS = [
      {
        name: "Operation „Weiß“",
        headquarters_code: "germany_headquarters_operation_weiß",
        card_codes: %w[
          germany_pz_ii_l_luchs
          germany_pz_iii_j
          germany_pz_iv_h
          germany_tiger_i
          germany_jagdpanther
          germany_hummel
          germany_tocnyj_vystrel
          germany_radioperekhvat
          germany_grenaderskij_vzvod
          germany_flak_88
        ]
      },
      {
        name: "Second front",
        headquarters_code: "usa_headquarters_second_front",
        card_codes: %w[
          usa_m3_stuart
          usa_m4_sherman
          usa_m4a3e8_easy_eight
          usa_m26_pershing
          usa_m18_hellcat
          usa_m7_priest
          usa_lend_liz
          usa_ognevoj_nalyot
          usa_inzhenernyj_vzvod
          usa_vzvod_bazukometchikov
        ]
      },
      {
        name: "Западный фронт",
        headquarters_code: "ussr_headquarters_west_front",
        card_codes: %w[
          ussr_t_70
          ussr_t_34
          ussr_t_34_85
          ussr_is_2
          ussr_su_100
          ussr_su_26
          ussr_zalp_katyushi
          ussr_popolnenie
          ussr_strelkovyj_vzvod
          ussr_vzvod_ptr
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
