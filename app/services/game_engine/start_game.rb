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

      game_players = @game.game_players.includes(
        headquarters_card: [:headquarters, { card_abilities: :ability }]
      ).to_a

      raise ArgumentError, "Game must have exactly two players" unless game_players.size == 2

      participants = game_players.map do |game_player|
        cards = GameState.cards_from_deck(game_player.deck).shuffle

        {
          player_id: game_player.player_id,
          nation_id: game_player.nation_id,
          hand: cards.first(INITIAL_HAND_SIZE),
          deck: cards.drop(INITIAL_HAND_SIZE),
          headquarters: headquarters_from(game_player)
        }
      end

      current_player_id = participants.sample[:player_id]

      @game.transaction do
        state = GameState.initial(
          current_player_id: current_player_id,
          participants: participants
        )

        state["players"][current_player_id.to_s]["resources"] =
          GameEngine::Resources::FuelCalculator.call(
            state: state,
            player_id: current_player_id
          )

        @game.state = state
        @game.status = "started"
        @game.save!
      end

      @game
    end

    private

    def headquarters_from(game_player)
      card = game_player.headquarters_card
      headquarters = card.headquarters

      {
        "type" => "headquarters",
        "card_id" => card.id,
        "player_id" => game_player.player_id,
        "nation_id" => card.nation_id,
        "name" => card.name,
        "hp" => headquarters.hp,
        "firepower" => headquarters.firepower,
        "fuel" => headquarters.fuel,
        "has_attacked" => false,
        "has_counterattacked" => false,
        "abilities" => card.card_abilities.map do |card_ability|
          { "code" => card_ability.ability.code }.merge(card_ability.parameters)
        end
      }
    end
  end
end
