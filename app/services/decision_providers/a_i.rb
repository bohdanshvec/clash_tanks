# app/services/decision_providers/a_i.rb

module DecisionProviders
  class AI < Base
    MAX_ATTEMPTS = 3

    class InvalidDecision < StandardError
    end

		def initialize(context:, decision_source: nil)
			super(context: context)
			@decision_source = decision_source || method(:call_default_adapter)
		end

    def call
      attempts = 0

      loop do
        attempts += 1

        begin
          decision = @decision_source.call(context.visible_state)
          return build_action(decision)
        rescue InvalidDecision => error
          if attempts >= MAX_ATTEMPTS
            raise ArgumentError,
                  "AI failed to produce a valid decision after " \
                  "#{MAX_ATTEMPTS} attempts: #{error.message}"
          end
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
			else
				raise ArgumentError,
				      "Unsupported AI_PROVIDER: #{ENV.fetch("AI_PROVIDER")}"
			end
		end

    def build_action(decision)
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
