module DecisionProviders
  class Context
    attr_reader :player_id, :visible_state

    def initialize(state:, player_id:)
      @player_id = player_id.to_s

      @visible_state = GameEngine::VisibleState.call(
        state: state,
        player_id: @player_id
      )

      deep_freeze(@visible_state)
      freeze
    end

    def available_actions
      @visible_state.fetch("available_actions")
    end

    private

    def deep_freeze(value)
      case value
      when Hash
        value.each do |key, item|
          deep_freeze(key)
          deep_freeze(item)
        end
      when Array
        value.each do |item|
          deep_freeze(item)
        end
      end

      value.freeze
    end
  end
end
