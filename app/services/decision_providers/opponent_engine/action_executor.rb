
module DecisionProviders
  module OpponentEngine
    class ActionExecutor
      class InvalidPlan < StandardError
      end

      Execution = Data.define(
        :action,
        :expected_visible_state,
        :next_step_index
      )

      def self.call(plan:, context:)
        new(plan:, context:).call
      end

      def self.execute(plan:, context:, step_index: 0)
        new(plan:, context:).execute(step_index:)
      end

      def initialize(plan:, context:)
        @plan = plan
        @context = context
      end

      # Сохраняет прежний интерфейс для существующего AI.
      def call
        actions = @plan.actions

        unless actions.is_a?(Array) && actions.any?
          raise InvalidPlan, "Opponent engine returned an empty plan"
        end

        build_action(actions.first)
      end

      # Возвращает действие вместе с ожидаемым состоянием после него.
      def execute(step_index: 0)
        index = Integer(step_index)

        unless index >= 0
          raise InvalidPlan, "Plan step index must not be negative"
        end

        actions = @plan.actions
        steps = @plan.steps

        unless actions.is_a?(Array) && steps.is_a?(Array)
          raise InvalidPlan, "Opponent engine returned an invalid plan"
        end

        unless actions.any? && steps.any?
          raise InvalidPlan, "Opponent engine returned an empty plan"
        end

        unless actions.length == steps.length
          raise InvalidPlan, "Plan actions and steps have different lengths"
        end

        step = steps[index]

        unless step
          raise InvalidPlan, "Plan step does not exist"
        end

        decision = step.action
        expected_state = step.expected_visible_state

        unless decision == actions[index]
          raise InvalidPlan, "Plan step action does not match plan actions"
        end

        unless expected_state.is_a?(Hash)
          raise InvalidPlan, "Plan step has an invalid expected state"
        end

        Execution.new(
          action: build_action(decision),
          expected_visible_state: expected_state.deep_dup,
          next_step_index: index + 1
        )
      rescue ArgumentError, TypeError
        raise InvalidPlan, "Plan step index must be an integer"
      end

      private

      def build_action(decision)
        unless decision.is_a?(Hash)
          raise InvalidPlan, "Planned action must be a Hash"
        end

        type = value_from(decision, "type")
        payload = value_from(decision, "payload") || {}

        unless type.is_a?(String) && type.present?
          raise InvalidPlan, "Planned action must contain a valid type"
        end

        unless payload.is_a?(Hash)
          raise InvalidPlan, "Planned action payload must be a Hash"
        end

        GameEngine::Action.new(
          player_id: @context.player_id,
          type: type,
          payload: normalize_payload(payload),
          expected_state_digest: @context.state_digest
        )
      end

      def value_from(hash, key)
        return hash[key] if hash.key?(key)

        hash[key.to_sym]
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
end
