module Matchmaking
  class Join
    def self.call(game:, player:, deck:)
      new(game: game, player: player, deck: deck).call
    end

    def initialize(game:, player:, deck:)
      @game = game
      @player = player
      @deck = deck
    end

    def call
      @game.with_lock do
        return nil unless @game.waiting?
        return nil unless @game.game_players.size == 1
        return nil if @game.game_players.exists?(player_id: @player.id)

        @game.game_players.create!(
          player: @player,
          nation: @deck.nation,
          deck: @deck,
          headquarters_card: @deck.headquarters_card
        )

        GameEngine::StartGame.call(@game)
      end

      @game
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    private

    attr_reader :game, :player, :deck
  end
end
