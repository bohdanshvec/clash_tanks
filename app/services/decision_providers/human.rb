module DecisionProviders
  class Human < Base
    def initialize(player_id:, type:, payload: {})
      @player_id = player_id
      @type = type
      @payload = payload
    end

    def call
      GameEngine::Action.new(
        player_id: @player_id,
        type: @type,
        payload: @payload
      )
    end
  end
end
