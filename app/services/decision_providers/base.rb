module DecisionProviders
  class Base
    def initialize(context:)
      @context = context
    end

    def call
      raise NotImplementedError, "#{self.class} must implement #call"
    end

    private

    attr_reader :context
  end
end
