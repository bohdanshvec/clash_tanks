require "test_helper"

class DecisionProviders::GroqAdapterTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:code, :body)

  class FakeHttpTransport
    attr_reader :uri, :request, :calls

    def initialize(response)
      @response = response
      @calls = 0
    end

    def call(uri, request)
      @calls += 1
      @uri = uri
      @request = request
      @response
    end
  end

  setup do
    @visible_state = {
      "status" => "started",
      "current_player_id" => "1",
      "players" => {
        "1" => {
          "hand" => []
        }
      },
      "available_actions" => {
        "field" => {
          "0,4" => {
            "moves" => [],
            "attacks" => [[2, 0]]
          }
        },
        "hand" => {}
      }
    }

    @legal_actions = [
      {
        "type" => "attack",
        "payload" => {
          "attacker" => [0, 4],
          "target" => [2, 0]
        }
      },
      {
        "type" => "end_turn",
        "payload" => {}
      }
    ]
  end

  test "returns the legal action selected by index zero" do
    transport = FakeHttpTransport.new(
      groq_response('{"action_index":0}')
    )

    adapter = build_adapter(transport)

    result = adapter.call(@visible_state)

    assert_equal @legal_actions.first, result
    assert_equal 1, transport.calls
  end

  test "returns the legal action selected by index one" do
    transport = FakeHttpTransport.new(
      groq_response('{"action_index":1}')
    )

    adapter = build_adapter(transport)

    result = adapter.call(@visible_state)

    assert_equal @legal_actions.second, result
    assert_equal 1, transport.calls
  end

  test "sends the optimized visible state and legal actions separately" do
    transport = FakeHttpTransport.new(
      groq_response('{"action_index":0}')
    )

    adapter = build_adapter(transport, model: "test-model")

    adapter.call(@visible_state)

    assert_equal(
      URI("https://api.groq.com/openai/v1/chat/completions"),
      transport.uri
    )

    assert_equal "Bearer test-api-key",
                 transport.request["Authorization"]

    assert_equal "application/json",
                 transport.request["Content-Type"]

    body = JSON.parse(transport.request.body)

    assert_equal "test-model", body["model"]
    assert_equal "json_schema", body.dig("response_format", "type")
    assert_equal DecisionProviders::GroqAdapter::INSTRUCTIONS,
                 body.dig("messages", 0, "content")

    user_content = JSON.parse(body.dig("messages", 1, "content"))

    expected_game_state = @visible_state.except(
      "available_actions",
      "status",
      "turn_started_at",
      "server_time",
      "result"
    )

    assert_equal expected_game_state, user_content["game_state"]

    %w[
      available_actions
      status
      turn_started_at
      server_time
      result
    ].each do |key|
      assert_not user_content["game_state"].key?(key)
    end

    assert_equal @legal_actions, user_content["legal_actions"]
  end

  test "does not modify the original visible state when preparing the request" do
    original_state = @visible_state.deep_dup

    transport = FakeHttpTransport.new(
      groq_response('{"action_index":0}')
    )

    adapter = build_adapter(transport)

    adapter.call(@visible_state)

    assert_equal original_state, @visible_state
    assert @visible_state.key?("available_actions")
  end

  test "skips Groq API when only one legal action is available" do
    visible_state = @visible_state.deep_dup

    visible_state["available_actions"]["field"] = {}

    transport = FakeHttpTransport.new(
      groq_response('{"action_index":0}')
    )

    adapter = build_adapter(transport)

    result = adapter.call(visible_state)

    assert_equal(
      {
        "type" => "end_turn",
        "payload" => {}
      },
      result
    )

    assert_equal 0, transport.calls
  end

  test "logs token usage when Groq returns usage statistics" do
    response_body = {
      "choices" => [
        {
          "message" => {
            "content" => '{"action_index":0}'
          }
        }
      ],
      "usage" => {
        "prompt_tokens" => 1200,
        "completion_tokens" => 10,
        "total_tokens" => 1210
      }
    }.to_json

    transport = FakeHttpTransport.new(
      FakeResponse.new("200", response_body)
    )

    adapter = build_adapter(transport)

    log_output = capture_log_output do
      adapter.call(@visible_state)
    end

    assert_includes log_output, "prompt_tokens=1200"
    assert_includes log_output, "completion_tokens=10"
    assert_includes log_output, "total_tokens=1210"
  end

  test "continues when Groq does not return token usage statistics" do
    transport = FakeHttpTransport.new(
      groq_response('{"action_index":0}')
    )

    adapter = build_adapter(transport)

    result = nil

    assert_nothing_raised do
      result = adapter.call(@visible_state)
    end

    assert_equal @legal_actions.first, result
  end

  test "rejects a negative action index" do
    transport = FakeHttpTransport.new(
      groq_response('{"action_index":-1}')
    )

    adapter = build_adapter(transport)

    assert_raises(DecisionProviders::GroqAdapter::RequestError) do
      adapter.call(@visible_state)
    end
  end

  test "rejects an action index outside the legal actions list" do
    transport = FakeHttpTransport.new(
      groq_response('{"action_index":2}')
    )

    adapter = build_adapter(transport)

    assert_raises(DecisionProviders::GroqAdapter::RequestError) do
      adapter.call(@visible_state)
    end
  end

  test "rejects a missing action index" do
    transport = FakeHttpTransport.new(
      groq_response("{}")
    )

    adapter = build_adapter(transport)

    assert_raises(DecisionProviders::GroqAdapter::RequestError) do
      adapter.call(@visible_state)
    end
  end

  test "rejects a non-integer action index" do
    transport = FakeHttpTransport.new(
      groq_response('{"action_index":"0"}')
    )

    adapter = build_adapter(transport)

    assert_raises(DecisionProviders::GroqAdapter::RequestError) do
      adapter.call(@visible_state)
    end
  end

  test "does not make a request when there are no legal actions" do
    transport = FakeHttpTransport.new(
      groq_response('{"action_index":0}')
    )

    adapter = build_adapter(transport)

    finished_state = @visible_state.merge("status" => "finished")

    error = assert_raises(DecisionProviders::GroqAdapter::RequestError) do
      adapter.call(finished_state)
    end

    assert_equal "No legal AI actions available", error.message
    assert_equal 0, transport.calls
  end

  test "raises an error when Groq returns HTTP 429 without retry instructions" do
    transport = FakeHttpTransport.new(
      FakeResponse.new(
        "429",
        '{"error":{"message":"Rate limit exceeded"}}'
      )
    )

    adapter = build_adapter(transport)

    error = assert_raises(DecisionProviders::GroqAdapter::RequestError) do
      adapter.call(@visible_state)
    end

    assert_match(/HTTP 429/, error.message)
    assert_equal 1, transport.calls
  end

  test "raises an error when Groq returns a non-success HTTP status" do
    transport = FakeHttpTransport.new(
      FakeResponse.new("500", '{"error":{"message":"Internal error"}}')
    )

    adapter = build_adapter(transport)

    error = assert_raises(DecisionProviders::GroqAdapter::RequestError) do
      adapter.call(@visible_state)
    end

    assert_match(/HTTP 500/, error.message)
    assert_equal 1, transport.calls
  end

  test "raises an error when the Groq response body is invalid JSON" do
    transport = FakeHttpTransport.new(
      FakeResponse.new("200", "not JSON")
    )

    adapter = build_adapter(transport)

    assert_raises(DecisionProviders::GroqAdapter::RequestError) do
      adapter.call(@visible_state)
    end
  end

  test "raises an error when the response has no decision content" do
    response_body = {
      "choices" => [
        {
          "message" => {
            "content" => nil
          }
        }
      ]
    }.to_json

    transport = FakeHttpTransport.new(
      FakeResponse.new("200", response_body)
    )

    adapter = build_adapter(transport)

    assert_raises(DecisionProviders::GroqAdapter::RequestError) do
      adapter.call(@visible_state)
    end
  end

  test "raises an error when the decision is not a JSON object" do
    transport = FakeHttpTransport.new(
      groq_response('["not","an","object"]')
    )

    adapter = build_adapter(transport)

    assert_raises(DecisionProviders::GroqAdapter::RequestError) do
      adapter.call(@visible_state)
    end
  end

  test "raises an error when the decision content is invalid JSON" do
    transport = FakeHttpTransport.new(
      groq_response("not JSON")
    )

    adapter = build_adapter(transport)

    assert_raises(DecisionProviders::GroqAdapter::RequestError) do
      adapter.call(@visible_state)
    end
  end

  test "raises a configuration error when the API key is missing" do
    assert_raises(DecisionProviders::GroqAdapter::ConfigurationError) do
      DecisionProviders::GroqAdapter.new(api_key: nil)
    end
  end

  test "sends reasoning optimization parameters" do
    transport = FakeHttpTransport.new(
      groq_response('{"action_index":0}')
    )

    adapter = build_adapter(transport)

    adapter.call(@visible_state)

    body = JSON.parse(transport.request.body)

    assert_equal "low", body["reasoning_effort"]
    assert_equal 512, body["max_completion_tokens"]

    assert_equal(
      {
        "type" => "json_schema",
        "json_schema" => {
          "name" => "ai_action_selection",
          "strict" => true,
          "schema" => {
            "type" => "object",
            "properties" => {
              "action_index" => {
                "type" => "integer"
              }
            },
            "required" => ["action_index"],
            "additionalProperties" => false
          }
        }
      },
      body["response_format"]
    )
  end

  test "returns original legal action with optimization enabled" do
    transport = FakeHttpTransport.new(
      groq_response('{"action_index":0}')
    )

    adapter = build_adapter(transport)

    result = adapter.call(@visible_state)

    assert_equal @legal_actions.first, result
    assert_equal "attack", result["type"]

    assert_equal(
      {
        "attacker" => [0, 4],
        "target" => [2, 0]
      },
      result["payload"]
    )
  end

  test "raises InvalidJsonGeneration for json_validate_failed" do
    response_body = {
      error: {
        message: "Failed to validate JSON",
        type: "invalid_request_error",
        code: "json_validate_failed"
      }
    }.to_json

    transport = FakeHttpTransport.new(
      FakeResponse.new("400", response_body)
    )

    adapter = build_adapter(transport)

    error = assert_raises(
      DecisionProviders::GroqAdapter::InvalidJsonGeneration
    ) do
      adapter.call(@visible_state)
    end

    assert_equal(
      "Groq API failed to generate valid JSON",
      error.message
    )

    assert_equal 1, transport.calls
  end

  test "does not classify other HTTP 400 errors as InvalidJsonGeneration" do
    response_body = {
      error: {
        message: "Invalid request parameters",
        type: "invalid_request_error",
        code: "invalid_request"
      }
    }.to_json

    transport = FakeHttpTransport.new(
      FakeResponse.new("400", response_body)
    )

    adapter = build_adapter(transport)

    error = assert_raises(
      DecisionProviders::GroqAdapter::RequestError
    ) do
      adapter.call(@visible_state)
    end

    assert_instance_of(
      DecisionProviders::GroqAdapter::RequestError,
      error
    )

    assert_equal "Groq API returned HTTP 400", error.message
    assert_equal 1, transport.calls
  end

  private

  def build_adapter(transport, model: "openai/gpt-oss-20b", sleeper: nil)
    DecisionProviders::GroqAdapter.new(
      api_key: "test-api-key",
      model: model,
      http_transport: transport,
      sleeper: sleeper
    )
  end

  def groq_response(content, code: "200")
    body = {
      "choices" => [
        {
          "message" => {
            "content" => content
          }
        }
      ]
    }.to_json

    FakeResponse.new(code, body)
  end

  def capture_log_output
    output = StringIO.new
    original_logger = Rails.logger

    Rails.logger = ActiveSupport::Logger.new(output)

    yield

    output.string
  ensure
    Rails.logger = original_logger
  end
end
