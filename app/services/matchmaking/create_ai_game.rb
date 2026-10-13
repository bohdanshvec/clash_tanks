module Matchmaking
  class CreateAiGame
    def self.call(player:, deck:)
      new(player: player, deck: deck).call
    end

    def initialize(player:, deck:)
      @player = player
      @deck = deck
    end

    def call
      validate_player_and_deck!

      ai_deck = Matchmaking::AiDeckSelector.call(
        player_deck: deck
      )

      unless ai_deck
        raise ArgumentError, "No compatible AI deck"
      end

      Game.transaction do
        game = Game.create!(
          mode: "ai",
          status: "waiting"
        )

        game.game_players.create!(
          player: player,
          nation: deck.nation,
          deck: deck,
          headquarters_card: deck.headquarters_card
        )

        game.game_players.create!(
          player: ai_deck.player,
          nation: ai_deck.nation,
          deck: ai_deck,
          headquarters_card: ai_deck.headquarters_card
        )

        GameEngine::StartGame.call(game)

        game
      end
    end

    private

    attr_reader :player, :deck

    def validate_player_and_deck!
      if player.ai?
        raise ArgumentError, "AI cannot create a game as human"
      end

      unless deck.player_id == player.id
        raise ArgumentError, "Deck does not belong to player"
      end

      unless deck.complete?
        raise ArgumentError, "Deck is not complete"
      end
    end
  end
end
