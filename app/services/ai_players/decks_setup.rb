
module AiPlayers
  class DecksSetup
    DECKS = [
      {
        name: "АІ — США: важка техніка",
        nation_code: "usa",
        headquarters_code: "usa_headquarters_second_front",
        card_codes: {
          "usa_m4_sherman" => 1,
          "usa_m4a3e2" => 3,
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
          "germany_hetzer" => 2,
          "germany_pz_iv_ausf" => 3,
          "germany_postril" => 1
        }
      }
    ].freeze

    def self.call
      new.call
    end

    def call
      player = AiPlayers::Setup.call

      desired_names = DECKS.map { |definition| definition[:name] }

      # Удаляем AI-колоды, которые больше не присутствуют
      # в конфигурации DECKS.
      player.decks.where.not(name: desired_names).find_each do |deck|
        Decks::Destroy.call(deck: deck)
      end

      DECKS.map do |definition|
        sync_deck(player, definition)
      end
    end

    private

    def sync_deck(player, definition)
      nation = Nation.find_by!(code: definition[:nation_code])

      headquarters_card = Card.find_by!(
        code: definition[:headquarters_code]
      )

      cards = definition[:card_codes].map do |code, quantity|
        card = Card.find_by!(code: code)

        validate_card!(card, nation, quantity)

        [card, quantity]
      end

      validate_deck_size!(cards)

      deck = Deck.find_by(
        player: player,
        name: definition[:name]
      )

      unless deck
        return create_deck(
          player: player,
          definition: definition,
          nation: nation,
          headquarters_card: headquarters_card,
          cards: cards
        )
      end

      return deck if unchanged?(
        deck,
        nation,
        headquarters_card,
        cards
      )

      Decks::Change.call(deck: deck) do |locked_deck|
        locked_deck.update!(
          name: definition[:name],
          nation: nation,
          headquarters_card: headquarters_card
        )

        locked_deck.deck_cards.delete_all

        cards.each do |card, quantity|
          locked_deck.deck_cards.create!(
            card: card,
            quantity: quantity
          )
        end

        locked_deck
      end
    end

    def create_deck(player:, definition:, nation:, headquarters_card:, cards:)
      Deck.transaction do
        deck = Deck.create!(
          player: player,
          name: definition[:name],
          nation: nation,
          headquarters_card: headquarters_card
        )

        cards.each do |card, quantity|
          deck.deck_cards.create!(
            card: card,
            quantity: quantity
          )
        end

        deck
      end
    end

    def unchanged?(deck, nation, headquarters_card, cards)
      return false unless deck.nation_id == nation.id
      return false unless deck.headquarters_card_id == headquarters_card.id

      current_cards = deck.deck_cards.includes(:card).each_with_object({}) do |deck_card, result|
        result[deck_card.card.code] = deck_card.quantity
      end

      desired_cards = cards.to_h do |card, quantity|
        [card.code, quantity]
      end

      current_cards == desired_cards
    end

    def validate_card!(card, nation, quantity)
      unless card.nation_id == nation.id
        raise ArgumentError,
          "Card #{card.code} belongs to another nation"
      end

      if card.card_type == "headquarters"
        raise ArgumentError,
          "Headquarters card #{card.code} cannot be in the deck"
      end

      unless quantity.is_a?(Integer) && quantity.between?(1, 3)
        raise ArgumentError,
          "Invalid quantity for card #{card.code}: #{quantity.inspect}"
      end
    end

    def validate_deck_size!(cards)
      total = cards.sum { |_card, quantity| quantity }

      unless total == Deck::DECK_SIZE
        raise ArgumentError,
          "AI deck must contain exactly #{Deck::DECK_SIZE} cards, got #{total}"
      end
    end
  end
end
