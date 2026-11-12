module DecisionProviders
  class AI < Base
    MAX_ATTEMPTS = 3

    class InvalidDecision < StandardError
    end

    PlanDecision = Data.define(
      :action,
      :plan,
      :expected_visible_state,
      :next_step_index
    )

    RETRYABLE_DECISION_ERRORS = [
      InvalidDecision,
      GroqAdapter::InvalidActionIndex,
      GroqAdapter::InvalidJsonGeneration
    ].freeze

    def initialize(context:, decision_source: nil)
      super(context: context)

      @uses_default_adapter = decision_source.nil?
      @decision_source = decision_source || method(:call_default_adapter)
    end

    def call
      attempts = 0

      loop do
        attempts += 1

        begin
          decision = @decision_source.call(context.visible_state)
          return build_action(decision)
        rescue *RETRYABLE_DECISION_ERRORS => error
          raise_attempts_exhausted(error) if attempts >= MAX_ATTEMPTS

          log_invalid_decision(error, attempts)
        end
      end
    end

    # Возвращает действие и информацию о плане для собственного движка.
    # Для остальных провайдеров сохраняет прежнее поведение.
    def call_with_plan
      unless opponent_engine_provider?
        return PlanDecision.new(
          action: call,
          plan: nil,
          expected_visible_state: nil,
          next_step_index: nil
        )
      end

      attempts = 0

      loop do
        attempts += 1

        begin
          return call_opponent_engine_with_plan
        rescue *RETRYABLE_DECISION_ERRORS => error
          raise_attempts_exhausted(error) if attempts >= MAX_ATTEMPTS

          log_invalid_decision(error, attempts)
        end
      end
    end

    private

    def call_default_adapter(visible_state)
      case ENV.fetch("AI_PROVIDER", "groq").downcase
      when "groq"
        GroqAdapter.new.call(visible_state)
      when "openai"
        OpenAiAdapter.new.call(visible_state)
      when "opponent_engine"
        call_opponent_engine(visible_state)
      else
        raise ArgumentError,
              "Unsupported AI_PROVIDER: #{ENV.fetch('AI_PROVIDER')}"
      end
    end

    def opponent_engine_provider?
      @uses_default_adapter &&
        ENV.fetch("AI_PROVIDER", "groq").downcase == "opponent_engine"
    end

    def call_opponent_engine(visible_state)
      call_opponent_engine_with_plan.action
    end

    def call_opponent_engine_with_plan
      current_time = Time.iso8601(
        context.visible_state.fetch("server_time")
      )

      plan = OpponentEngine::Planning::TacticalPlanner.call(
        visible_state: context.visible_state,
        player_id: context.player_id,
        current_time: current_time
      )

      execution = OpponentEngine::ActionExecutor.execute(
        plan: plan,
        context: context
      )

      PlanDecision.new(
        action: execution.action,
        plan: plan,
        expected_visible_state: execution.expected_visible_state,
        next_step_index: execution.next_step_index
      )
    end

    def raise_attempts_exhausted(error)
      raise ArgumentError,
            "AI failed to produce a valid decision after " \
            "#{MAX_ATTEMPTS} attempts (#{error.class})"
    end

    def log_invalid_decision(error, attempts)
      Rails.logger.warn(
        "[DecisionProviders::AI] Invalid decision: " \
        "error_class=#{error.class}, " \
        "retry=#{attempts}/#{MAX_ATTEMPTS}"
      )
    end

    def build_action(decision)
      if decision.is_a?(GameEngine::Action)
        return validate_prebuilt_action(decision)
      end

      unless decision.is_a?(Hash)
        raise InvalidDecision, "AI decision must be a Hash"
      end

      type = decision["type"]
      payload = decision.fetch("payload", {})

      unless type.is_a?(String) && type.present?
        raise InvalidDecision,
              "AI decision must contain a valid action type"
      end

      unless payload.is_a?(Hash)
        raise InvalidDecision, "AI decision payload must be a Hash"
      end

      GameEngine::Action.new(
        player_id: context.player_id,
        type: type,
        payload: normalize_payload(payload),
        expected_state_digest: context.state_digest
      )
    end

    def validate_prebuilt_action(action)
      unless action.player_id.to_s == context.player_id
        raise InvalidDecision, "AI action has an invalid player_id"
      end

      unless action.expected_state_digest == context.state_digest
        raise InvalidDecision, "AI action has an invalid state digest"
      end

      action
    end

    def normalize_payload(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, item), result|
          normalized_key = key.respond_to?(:to_sym) ? key.to_sym : key
          result[normalized_key] = normalize_payload(item)
        end
      when Array
        value.map { |item| normalize_payload(item) }
      else
        value
      end
    end
  end
end
