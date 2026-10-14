require "test_helper"

class DecisionProvidersGroqAdapterTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:code, :body)

  class FakeHttpTransport
    attr_reader :uri, :request

    def initialize(response)
      @response = response
    end

    def call(uri, request)
      @uri = uri
      @request = request
      @response
    end
  end

  test "converts a valid Groq response into a decision hash" do
    response = FakeResponse.new(
      "200",
      JSON.generate(
        choices: [
          {
            message: {
              content: '{"type":"end_turn","payload":{}}'
            }
          }
        ]
      )
    )

    transport = FakeHttpTransport.new(response)

    adapter = DecisionProviders::GroqAdapter.new(
      api_key: "test-api-key",
      model: "test-model",
      http_transport: transport
    )

    decision = adapter.call(
      "current_player_id" => "1",
      "available_actions" => {}
    )

    assert_equal(
      {
        "type" => "end_turn",
        "payload" => {}
      },
      decision
    )

    assert_equal(
      DecisionProviders::GroqAdapter::API_URL,
      transport.uri.to_s
    )

    assert_equal "Bearer test-api-key", transport.request["Authorization"]
    assert_equal "application/json", transport.request["Content-Type"]

    request_body = JSON.parse(transport.request.body)

    assert_equal "test-model", request_body["model"]
    assert_equal "json_object", request_body.dig("response_format", "type")
    assert_equal(
      DecisionProviders::GroqAdapter::INSTRUCTIONS,
      request_body.dig("messages", 0, "content")
    )
  end

  test "sends the visible game state as JSON" do
    response = FakeResponse.new(
      "200",
      JSON.generate(
        choices: [
          {
            message: {
              content: '{"type":"end_turn","payload":{}}'
            }
          }
        ]
      )
    )

    transport = FakeHttpTransport.new(response)

    adapter = DecisionProviders::GroqAdapter.new(
      api_key: "test-api-key",
      http_transport: transport
    )

    visible_state = {
      "current_player_id" => "1",
      "available_actions" => {
        "field" => {},
        "hand" => {}
      }
    }

    adapter.call(visible_state)

    request_body = JSON.parse(transport.request.body)
    input = request_body.dig("messages", 1, "content")

    assert_includes input, JSON.generate(visible_state)
  end

  test "raises RequestError for an unsuccessful HTTP response" do
    response = FakeResponse.new("429", '{"error":"rate limit"}')
    transport = FakeHttpTransport.new(response)

    adapter = DecisionProviders::GroqAdapter.new(
      api_key: "test-api-key",
      http_transport: transport
    )

    error = assert_raises(
      DecisionProviders::GroqAdapter::RequestError
    ) do
      adapter.call({})
    end

    assert_equal "Groq API returned HTTP 429", error.message
  end

  test "raises RequestError when the response has no decision content" do
    response = FakeResponse.new(
      "200",
      JSON.generate(choices: [{ message: { content: nil } }])
    )

    adapter = DecisionProviders::GroqAdapter.new(
      api_key: "test-api-key",
      http_transport: FakeHttpTransport.new(response)
    )

    assert_raises(
      DecisionProviders::GroqAdapter::RequestError
    ) do
      adapter.call({})
    end
  end

  test "raises RequestError when the decision is not a JSON object" do
    response = FakeResponse.new(
      "200",
      JSON.generate(
        choices: [
          {
            message: {
              content: '["not","an","object"]'
            }
          }
        ]
      )
    )

    adapter = DecisionProviders::GroqAdapter.new(
      api_key: "test-api-key",
      http_transport: FakeHttpTransport.new(response)
    )

    assert_raises(
      DecisionProviders::GroqAdapter::RequestError
    ) do
      adapter.call({})
    end
  end

  test "raises RequestError when the response body is invalid JSON" do
    response = FakeResponse.new("200", "not JSON")

    adapter = DecisionProviders::GroqAdapter.new(
      api_key: "test-api-key",
      http_transport: FakeHttpTransport.new(response)
    )

    error = assert_raises(
      DecisionProviders::GroqAdapter::RequestError
    ) do
      adapter.call({})
    end

    assert_equal "Groq API returned invalid JSON", error.message
  end

  test "raises ConfigurationError when the API key is missing" do
    assert_raises(
      DecisionProviders::GroqAdapter::ConfigurationError
    ) do
      DecisionProviders::GroqAdapter.new(api_key: nil)
    end
  end
end
