module GameEngine
  class StartGame
    INITIAL_HAND_SIZE = 6

    def self.call(game)
      new(game).call
    end

    def initialize(game)
      @game = game
    end

    def call
      raise ArgumentError, "Game must be waiting" unless @game.waiting?

      game_players = @game.game_players.to_a

      raise ArgumentError, "Game must have exactly two players" unless game_players.size == 2

      participants = game_players.map do |game_player|
        cards = GameState.cards_from_deck(game_player.deck).shuffle

        {
          player_id: game_player.player_id,
          nation_id: game_player.nation_id,
          hand: cards.first(INITIAL_HAND_SIZE),
          deck: cards.drop(INITIAL_HAND_SIZE)
        }
      end

      current_player_id = participants.sample[:player_id]

      @game.transaction do
        @game.state = GameState.initial(
          current_player_id: current_player_id,
          participants: participants
        )
        @game.status = "started"
        @game.save!
      end

      @game
    end
  end
end
