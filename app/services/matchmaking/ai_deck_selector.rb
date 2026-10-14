module Matchmaking
  class AiDeckSelector
    TOLERANCE = 0.10

    def self.call(player_deck:)
      new(player_deck: player_deck).call
    end

    def initialize(player_deck:)
      @player_deck = player_deck
    end

    def call
      player_weight = player_deck.weight

      Deck
        .joins(:player)
        .where(players: { ai: true })
        .includes(:player)
        .select(&:complete?)
        .select do |ai_deck|
          compatible_weight?(
            player_weight: player_weight,
            ai_weight: ai_deck.weight
          )
        end
        .min_by do |ai_deck|
          (player_weight - ai_deck.weight).abs
        end
    end

    private

    attr_reader :player_deck

    def compatible_weight?(player_weight:, ai_weight:)
      minimum = ai_weight * (1 - TOLERANCE)
      maximum = ai_weight * (1 + TOLERANCE)

      player_weight.between?(minimum, maximum)
    end
  end
end
