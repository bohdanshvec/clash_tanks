require "json"
require "net/http"
require "timeout"
require "uri"

module DecisionProviders
  class GroqAdapter
    class ConfigurationError < StandardError
    end

    class RequestError < StandardError
    end

    API_URL = "https://api.groq.com/openai/v1/chat/completions"
    DEFAULT_MODEL = "openai/gpt-oss-20b"

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

    def initialize(
      api_key: ENV["GROQ_API_KEY"],
      model: ENV.fetch("GROQ_MODEL", DEFAULT_MODEL),
      http_transport: nil
    )
      @api_key = api_key
      @model = model
      @http_transport = http_transport

      if @api_key.blank?
        raise ConfigurationError, "GROQ_API_KEY is not configured"
      end
    end

    def call(visible_state)
      uri = URI(API_URL)

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"] = "application/json"

      request.body = JSON.generate(
        model: @model,
        messages: [
          {
            role: "system",
            content: INSTRUCTIONS
          },
          {
            role: "user",
            content: "Choose an action from this JSON game state:\n" \
                     "#{JSON.generate(visible_state)}"
          }
        ],
        response_format: {
          type: "json_object"
        }
      )

      response = send_request(uri, request)

      unless response.code.to_i.between?(200, 299)
        raise RequestError, "Groq API returned HTTP #{response.code}"
      end

      parse_response(response.body)
    rescue ConfigurationError, RequestError
      raise
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => error
      raise RequestError, "Groq API request timed out: #{error.class}"
    rescue SocketError, SystemCallError, IOError => error
      raise RequestError, "Groq API connection failed: #{error.class}"
    rescue JSON::ParserError
      raise RequestError, "Groq API returned invalid JSON"
    end

    private

    def send_request(uri, request)
      if @http_transport
        @http_transport.call(uri, request)
      else
        Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: true,
          open_timeout: 5,
          read_timeout: 20
        ) do |http|
          http.request(request)
        end
      end
    end

    def parse_response(body)
      data = JSON.parse(body)
      content = data.dig("choices", 0, "message", "content")

      unless content.is_a?(String) && content.present?
        raise RequestError, "Groq API response does not contain a decision"
      end

      begin
        decision = JSON.parse(content)
      rescue JSON::ParserError
        raise RequestError, "Groq API returned an invalid decision"
      end

      unless decision.is_a?(Hash)
        raise RequestError, "Groq API decision must be a JSON object"
      end

      decision
    rescue JSON::ParserError
      raise RequestError, "Groq API returned invalid JSON"
    end
  end
end
