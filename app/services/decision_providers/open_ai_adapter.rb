# app/services/decision_providers/open_ai_adapter.rb

require "json"

module DecisionProviders
  class OpenAiAdapter
    class ConfigurationError < StandardError
    end
    
    DEFAULT_MODEL = "gpt-4.1-mini"

    INSTRUCTIONS = <<~TEXT.freeze
      You are the AI decision provider for a turn-based tank card strategy game.

      You receive a JSON representation of the visible game state.
      The state includes the actions currently available to the player.

      Choose one action from the available actions.

      Return only a JSON object with this structure:
      {
        "type": "action_type",
        "payload": {}
      }

      Rules:
      - Use only information present in the supplied game state.
      - Do not invent action types or payload values.
      - Follow the available_actions information when choosing an action.
      - Do not return a player_id.
      - Do not return explanations, Markdown, or additional fields.
      - The game engine will independently validate your decision.
    TEXT

		def initialize(client: nil, model: nil)
			@client = client
			@model = model || ENV.fetch("OPENAI_MODEL", DEFAULT_MODEL)
		end

		def call(visible_state)
			response = client.responses.create(
				model: @model,
				instructions: INSTRUCTIONS,
				input: "Choose an action from the following JSON game state:\n" \
				       "#{JSON.generate(visible_state)}",
				text: {
				  format: {
				    type: "json_object"
				  }
				}
			)

			parse_decision(response.output_text)
		end

    private
    
    def client
			@client ||= build_client
		end

		def build_client
			api_key = ENV["OPENAI_API_KEY"]

			if api_key.blank?
				raise ConfigurationError,
				      "OPENAI_API_KEY is not configured"
			end

			OpenAI::Client.new(
				api_key: api_key,
				timeout: 20.0,
				max_retries: 1
			)
		end

    def parse_decision(output_text)
      return output_text unless output_text.is_a?(String)

      JSON.parse(output_text)
    rescue JSON::ParserError
      output_text
    end
  end
end
