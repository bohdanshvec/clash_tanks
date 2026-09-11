module GameEngine
  class Engine
    ACTIONS = {
    	"move" => Actions::Move,
    	"attack" => Actions::Attack,
      "end_turn" => Actions::EndTurn
    }.freeze

    def initialize(state)
      @state = state
    end

    def call(action)
      handler_class = ACTIONS[action.type]

      return failure("Unknown action type") unless handler_class

      handler_class.new(@state, action).call
    end

    private

    def failure(error)
      Result.new(
        success: false,
        error: error
      )
    end
  end
end
