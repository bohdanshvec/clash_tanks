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

    class InvalidActionIndex < RequestError
    end

    class InvalidJsonGeneration < RequestError
    end

    API_URL = "https://api.groq.com/openai/v1/chat/completions"
    DEFAULT_MODEL = "openai/gpt-oss-20b"

    DEFAULT_REASONING_EFFORT = "low"
    DEFAULT_MAX_COMPLETION_TOKENS = 512

    MAX_RATE_LIMIT_RETRIES = 3
    MAX_TOTAL_RATE_LIMIT_WAIT_SECONDS = 20

    MAX_TRANSIENT_RETRIES = 1
    TRANSIENT_RETRY_DELAY_SECONDS = 1

    TRANSIENT_NETWORK_ERRORS = [
      Net::OpenTimeout,
      Net::ReadTimeout,
      Timeout::Error,
      SocketError,
      SystemCallError,
      IOError
    ].freeze

    INSTRUCTIONS = <<~TEXT.freeze
      You play Clash Tanks, a turn-based tank card strategy inspired by
      World of Tanks Generals. The battlefield is a 3x5 grid.

      OBJECTIVE:
      Destroy the enemy headquarters while protecting your own.
      Choose actions that improve your chances of winning.

      STRATEGY:
      - Destroy the enemy headquarters immediately when possible.
      - Protect your headquarters from imminent threats.
      - Deploy useful vehicles to defend your headquarters, control
        the battlefield, and pressure the enemy.
      - Fuel is recalculated each turn from your headquarters, vehicles,
        and platoons. Unspent fuel does not carry over.
      - Spend fuel efficiently on useful vehicles, platoons, and orders.
        Do not end your turn with affordable, valuable plays available.
      - Vehicles and platoons with positive fuel improve future income.
      - Focus attacks on dangerous enemy units until they are destroyed.
      - Attackers strike first. Destroying a target prevents retaliation.
      - A unit can counterattack only once per opponent's turn.
        Exploit exhausted counterattacks to minimize your losses.
      - Avoid attacks where retaliation causes unnecessary losses.
      - Use movement to improve attacking and defensive positions.
      - Light tanks can move twice. Medium tanks can move diagonally.
      - Tank destroyers fire first when attacked by ordinary tanks
        from adjacent cells.
      - Artillery can attack distant targets without retaliation when
        your vehicle or headquarters is adjacent to the target.
      - Headquarters can attack enemy headquarters at any distance,
        without retaliation from the enemy headquarters.
      - Platoons strengthen and protect headquarters, but firing the
        headquarters consumes HP from contributing platoons.
      - End your turn when no useful actions remain.
      - Never surrender.

      DECISION:
      You receive the visible game state and server-generated legal_actions.
      Choose exactly one action from legal_actions.
      Never invent or modify actions, IDs, coordinates, or payloads.
      Never assume hidden opponent information.

      Return only a JSON object: {"action_index": 0}
      The index must exist in legal_actions.
      Do not return explanations or additional fields.
    TEXT

    def initialize(
      api_key: ENV["GROQ_API_KEY"],
      model: ENV.fetch("GROQ_MODEL", DEFAULT_MODEL),
      reasoning_effort: DEFAULT_REASONING_EFFORT,
      max_completion_tokens: DEFAULT_MAX_COMPLETION_TOKENS,
      http_transport: nil,
      sleeper: nil
    )
      @api_key = api_key
      @model = model
      @reasoning_effort = reasoning_effort
      @max_completion_tokens = max_completion_tokens
      @http_transport = http_transport
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }

      if @api_key.blank?
        raise ConfigurationError, "GROQ_API_KEY is not configured"
      end

      unless %w[none low medium high].include?(@reasoning_effort)
        raise ConfigurationError,
              "Invalid reasoning_effort: #{@reasoning_effort}"
      end

      unless @max_completion_tokens.is_a?(Integer) &&
             @max_completion_tokens.positive?
        raise ConfigurationError,
              "max_completion_tokens must be a positive integer"
      end
    end

    def call(visible_state)
      legal_actions = DecisionProviders::ActionOptions.call(visible_state)

      if legal_actions.empty?
        raise RequestError, "No legal AI actions available"
      end
      
      if legal_actions.one?
        Rails.logger.info(
          "[GroqAdapter] Only one legal action available: " \
          "#{legal_actions.first['type'].inspect}. " \
          "Skipping Groq API request."
        )

        return legal_actions.first
      end

      uri = URI(API_URL)

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"] = "application/json"

      # Передаём модели только данные, необходимые для принятия решения.
      # available_actions уже преобразованы в legal_actions.
      # Остальные исключённые поля не влияют на тактический выбор.
      game_state_for_model = visible_state.except(
        "available_actions",
        "status",
        "turn_started_at",
        "server_time",
        "result"
      )

      request.body = JSON.generate(
        model: @model,
        reasoning_effort: @reasoning_effort,
        max_completion_tokens: @max_completion_tokens,
        messages: [
          {
            role: "system",
            content: INSTRUCTIONS
          },
          {
            role: "user",
            content: JSON.generate(
              game_state: game_state_for_model,
              legal_actions: legal_actions
            )
          }
        ],
        response_format: {
          type: "json_schema",
          json_schema: {
            name: "ai_action_selection",
            strict: true,
            schema: {
              type: "object",
              properties: {
                action_index: {
                  type: "integer"
                }
              },
              required: ["action_index"],
              additionalProperties: false
            }
          }
        }
      )

      response = send_request_with_retries(uri, request)

      unless response.code.to_i.between?(200, 299)
        log_http_error(response)
        raise RequestError, "Groq API returned HTTP #{response.code}"
      end

      log_token_usage(response.body)

      decision = parse_response(response.body)
      action_index = decision["action_index"]

      unless action_index.is_a?(Integer) &&
             action_index.between?(0, legal_actions.length - 1)
        Rails.logger.warn(
          "[GroqAdapter] Invalid action_index: " \
          "index=#{action_index.inspect}, " \
          "legal_actions_count=#{legal_actions.length}"
        )

        raise InvalidActionIndex,
              "Groq API returned an invalid action index"
      end

      legal_actions.fetch(action_index)
    rescue ConfigurationError, RequestError
      raise
    rescue *TRANSIENT_NETWORK_ERRORS => error
      raise RequestError,
            "Groq API request failed: #{error.class}"
    rescue JSON::ParserError
      raise RequestError, "Groq API returned invalid JSON"
    end

    private

    def send_request_with_retries(uri, request)
      rate_limit_retries = 0
      transient_retries = 0
      total_rate_limit_wait = 0

      loop do
        response = begin
          send_request_with_transient_retry(
            uri,
            request,
            transient_retries
          )
        rescue TransientRetryExhausted => error
          raise RequestError,
                "Groq API request failed after " \
                "#{MAX_TRANSIENT_RETRIES} retry: #{error.original_error.class}"
        end

        unless response.code.to_i == 429
          unless response.code.to_i.between?(200, 299)
            log_http_error(response)

            if response.code.to_i == 400 &&
               groq_error_code(response) == "json_validate_failed"
              raise InvalidJsonGeneration,
                    "Groq API failed to generate valid JSON"
            end

            raise RequestError,
                  "Groq API returned HTTP #{response.code}"
          end

          return response
        end

        retry_delay = rate_limit_retry_delay(response)

        if retry_delay.nil?
          log_http_error(response)

          raise RequestError,
                "Groq API returned HTTP 429 without a valid retry delay"
        end

        if rate_limit_retries >= MAX_RATE_LIMIT_RETRIES
          log_http_error(response)

          raise RequestError,
                "Groq API returned HTTP 429 after " \
                "#{rate_limit_retries} retries"
        end

        remaining_wait =
          MAX_TOTAL_RATE_LIMIT_WAIT_SECONDS - total_rate_limit_wait

        if retry_delay > remaining_wait
          log_http_error(response)

          Rails.logger.warn(
            "[GroqAdapter] Retry delay #{retry_delay}s exceeds " \
            "remaining wait budget #{remaining_wait}s."
          )

          raise RequestError,
                "Groq API rate-limit wait exceeds " \
                "#{MAX_TOTAL_RATE_LIMIT_WAIT_SECONDS} seconds"
        end

        rate_limit_retries += 1
        total_rate_limit_wait += retry_delay

        Rails.logger.warn(
          "[GroqAdapter] HTTP 429. " \
          "Retry #{rate_limit_retries}/#{MAX_RATE_LIMIT_RETRIES} " \
          "after #{retry_delay} seconds. " \
          "Total rate-limit wait: " \
          "#{total_rate_limit_wait}/" \
          "#{MAX_TOTAL_RATE_LIMIT_WAIT_SECONDS} seconds."
        )

        @sleeper.call(retry_delay)
      end
    end

    class TransientRetryExhausted < StandardError
      attr_reader :original_error

      def initialize(original_error)
        @original_error = original_error
        super(original_error.message)
      end
    end

    def send_request_with_transient_retry(uri, request, retries)
      send_request(uri, request)
    rescue *TRANSIENT_NETWORK_ERRORS => error
      if retries >= MAX_TRANSIENT_RETRIES
        Rails.logger.error(
          "[GroqAdapter] Transient network error after " \
          "#{retries} retries: #{error.class}: #{error.message}"
        )

        raise TransientRetryExhausted, error
      end

      Rails.logger.warn(
        "[GroqAdapter] Transient network error: " \
        "#{error.class}. Retrying once after " \
        "#{TRANSIENT_RETRY_DELAY_SECONDS} second."
      )

      @sleeper.call(TRANSIENT_RETRY_DELAY_SECONDS)

      send_request_with_transient_retry(
        uri,
        request,
        retries + 1
      )
    end

    def rate_limit_retry_delay(response)
      retry_after = response_header(response, "retry-after")

      if retry_after.present?
        delay = Float(retry_after, exception: false)
        return delay if delay&.positive?
      end

      body = response.body.to_s
      match = body.match(/try again in ([\d.]+)s/i)

      return nil unless match

      delay = Float(match[1], exception: false)
      delay if delay&.positive?
    end

    def response_header(response, name)
      response[name]
    rescue NameError, TypeError, IndexError
      nil
    end

    def groq_error_code(response)
      data = JSON.parse(response.body.to_s)
      data.dig("error", "code")
    rescue JSON::ParserError, TypeError
      nil
    end

    def log_http_error(response)
      error_details = [
        "HTTP #{response.code}",
        "retry-after=#{response_header(response, 'retry-after').inspect}",
        "remaining-requests=#{response_header(response, 'x-ratelimit-remaining-requests').inspect}",
        "remaining-tokens=#{response_header(response, 'x-ratelimit-remaining-tokens').inspect}",
        "body=#{response.body.to_s.truncate(2000)}"
      ].join("; ")

      Rails.logger.error("[GroqAdapter] #{error_details}")
    end

    def log_token_usage(body)
      data = JSON.parse(body)
      usage = data["usage"]

      unless usage.is_a?(Hash)
        Rails.logger.info(
          "[GroqAdapter] Token usage unavailable for model #{@model}"
        )
        return
      end

      prompt_tokens = usage["prompt_tokens"]
      completion_tokens = usage["completion_tokens"]
      total_tokens = usage["total_tokens"]

      reasoning_tokens = usage.dig(
        "completion_tokens_details",
        "reasoning_tokens"
      )

      finish_reason = data.dig(
        "choices",
        0,
        "finish_reason"
      )

      Rails.logger.info(
        "[GroqAdapter] Token usage: " \
        "model=#{@model}, " \
        "reasoning_effort=#{@reasoning_effort}, " \
        "max_completion_tokens=#{@max_completion_tokens}, " \
        "prompt_tokens=#{prompt_tokens.inspect}, " \
        "completion_tokens=#{completion_tokens.inspect}, " \
        "reasoning_tokens=#{reasoning_tokens.inspect}, " \
        "total_tokens=#{total_tokens.inspect}, " \
        "finish_reason=#{finish_reason.inspect}"
      )
    rescue JSON::ParserError
      Rails.logger.warn("[GroqAdapter] Could not parse token usage")
    end

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
        raise InvalidJsonGeneration,
              "Groq API response does not contain a decision"
      end

      begin
        decision = JSON.parse(content)
      rescue JSON::ParserError
        raise InvalidJsonGeneration,
              "Groq API returned an invalid decision"
      end

      unless decision.is_a?(Hash)
        raise InvalidJsonGeneration,
              "Groq API decision must be a JSON object"
      end

      decision
    rescue JSON::ParserError
      raise InvalidJsonGeneration,
            "Groq API returned invalid JSON"
    end
  end
end
