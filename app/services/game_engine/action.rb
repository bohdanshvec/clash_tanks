module GameEngine
  class Action
    attr_reader :player_id, :type, :payload

    def initialize(player_id:, type:, payload: {})
      @player_id = player_id
      @type = type
      @payload = payload.freeze
      freeze
    end
  end
end
