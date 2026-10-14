# test/services/decision_providers/open_ai_adapter_test.rb

require "test_helper"

class DecisionProvidersOpenAiAdapterTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:output_text)

  class FakeResponses
    attr_reader :arguments

    def initialize(response)
      @response = response
    end

    def create(**arguments)
      @arguments = arguments
      @response
    end
  end

  class FakeClient
    attr_reader :responses

    def initialize(response)
      @responses = FakeResponses.new(response)
    end
  end

  test "converts valid JSON response into a decision hash" do
    client = FakeClient.new(
      FakeResponse.new(
        '{"type":"end_turn","payload":{}}'
      )
    )

    adapter = DecisionProviders::OpenAiAdapter.new(
      client: client,
      model: "test-model"
    )

    decision = adapter.call(
      "current_player_id" => "1",
      "available_actions" => {
        "field" => {},
        "hand" => {}
      }
    )

    assert_equal(
      {
        "type" => "end_turn",
        "payload" => {}
      },
      decision
    )

    assert_equal "test-model", client.responses.arguments[:model]

    assert_equal(
      DecisionProviders::OpenAiAdapter::INSTRUCTIONS,
      client.responses.arguments[:instructions]
    )
  end

  test "sends visible state as JSON input" do
    client = FakeClient.new(
      FakeResponse.new('{"type":"end_turn","payload":{}}')
    )

    adapter = DecisionProviders::OpenAiAdapter.new(
      client: client,
      model: "test-model"
    )

    visible_state = {
      "current_player_id" => "1",
      "available_actions" => {
        "field" => {},
        "hand" => {}
      }
    }

    adapter.call(visible_state)

    request_input = client.responses.arguments[:input]

    # OpenAI JSON mode requires the word "JSON" in the input.
    assert_includes request_input, "JSON"

    # Remove the instruction line and parse the game state.
    input = JSON.parse(
      request_input.split("\n", 2).last
    )

    assert_equal "1", input["current_player_id"]
    assert input.key?("available_actions")

    assert_equal visible_state, input

    assert_equal(
      { format: { type: "json_object" } },
      client.responses.arguments[:text]
    )
  end

  test "returns invalid JSON text for the AI provider to reject" do
    invalid_response = "This is not JSON"

    client = FakeClient.new(
      FakeResponse.new(invalid_response)
    )

    adapter = DecisionProviders::OpenAiAdapter.new(
      client: client,
      model: "test-model"
    )

    decision = adapter.call({})

    assert_equal invalid_response, decision
  end

  test "returns non-string output unchanged" do
    client = FakeClient.new(
      FakeResponse.new(nil)
    )

    adapter = DecisionProviders::OpenAiAdapter.new(
      client: client,
      model: "test-model"
    )

    assert_nil adapter.call({})
  end

  test "raises a configuration error when API key is missing" do
    adapter = DecisionProviders::OpenAiAdapter.new(
      model: "test-model"
    )

    original_api_key = ENV["OPENAI_API_KEY"]
    ENV.delete("OPENAI_API_KEY")

    begin
      error = assert_raises(
        DecisionProviders::OpenAiAdapter::ConfigurationError
      ) do
        adapter.call({})
      end

      assert_equal(
        "OPENAI_API_KEY is not configured",
        error.message
      )
    ensure
      if original_api_key.nil?
        ENV.delete("OPENAI_API_KEY")
      else
        ENV["OPENAI_API_KEY"] = original_api_key
      end
    end
  end
end
