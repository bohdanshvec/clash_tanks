module GameEngine
  class StartGame
    def self.call(game)
      new(game).call
    end

    def initialize(game)
      @game = game
    end

    def call
      raise ArgumentError, "Game must be waiting" unless @game.waiting?

      player_ids = @game.game_players.pluck(:player_id)

      raise ArgumentError, "Game must have exactly two players" unless player_ids.size == 2

      current_player_id = player_ids.sample

      @game.transaction do
        @game.state = GameState.initial(
          current_player_id: current_player_id,
          player_ids: player_ids
        )
        @game.status = "started"
        @game.save!
      end

      @game
    end
  end
end
