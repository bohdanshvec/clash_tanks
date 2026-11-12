
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
      InvalidDecision
    ].freeze

    def initialize(context:, decision_source: nil)
      super(context: context)

      # decision_source сохраняется исключительно как механизм
      # внедрения тестовых решений.
      @decision_source = decision_source
    end

    def call
      call_with_plan.action
    end

    def call_with_plan
      if @decision_source
        return PlanDecision.new(
          action: call_injected_decision_source,
          plan: nil,
          expected_visible_state: nil,
          next_step_index: nil
        )
      end

      call_opponent_engine_with_plan
    end

    private

    def call_injected_decision_source
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

      Rails.logger.info(
        "[DecisionProviders::AI] Native opponent engine selected"
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
        "[DecisionProviders::AI] Invalid injected decision: " \
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
