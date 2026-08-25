module GameEngine
  class Result
    attr_reader :error, :state, :events

    def initialize(success:, error: nil, state: nil, events: [])
      @success = success
      @error = error
      @state = state
      @events = events.freeze
      freeze
    end

    def success?
      @success
    end
  end
end
