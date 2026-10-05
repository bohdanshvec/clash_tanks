module Matchmaking
  class FindOpponent
    ALLOWANCE_PERCENT = 15

    def self.call(player:, deck:)
      new(player: player, deck: deck).call
    end

    def initialize(player:, deck:)
      @player = player
      @deck = deck
    end

    def call
      candidates
        .select { |candidate| compatible?(candidate) }
        .min_by { |candidate| [weight_difference(candidate), candidate.created_at] }
    end

    private

    attr_reader :player, :deck

    def candidates
      Game
        .where(status: "waiting")
        .joins(:game_players)
        .includes(game_players: :deck)
        .select { |candidate| candidate.game_players.size == 1 }
    end

    def compatible?(candidate)
      candidate_player = candidate.game_players.first

      return false unless candidate_player
      return false if candidate_player.player_id == player.id

      first_weight = deck.weight
      second_weight = candidate_player.deck.weight
      difference = (first_weight - second_weight).abs

      difference <= first_weight * ALLOWANCE_PERCENT / 100.0 &&
        difference <= second_weight * ALLOWANCE_PERCENT / 100.0
    end

    def weight_difference(candidate)
      (candidate.game_players.first.deck.weight - deck.weight).abs
    end
  end
end
