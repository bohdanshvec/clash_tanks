require "test_helper"

class DecisionProvidersAITest < ActiveSupport::TestCase
  test "can initialize with the default OpenAI adapter without an API key" do
    provider = DecisionProviders::AI.new(
      context: build_context
    )

    assert_instance_of DecisionProviders::AI, provider
  end

  test "converts a decision into a game action" do
    context = build_context

    decision_source = lambda do |visible_state|
      assert_equal "1", visible_state["current_player_id"]

      {
        "type" => "end_turn",
        "payload" => {}
      }
    end

    action = DecisionProviders::AI.new(
      context: context,
      decision_source: decision_source
    ).call

    assert_instance_of GameEngine::Action, action
    assert_equal "1", action.player_id
    assert_equal "end_turn", action.type
    assert_equal({}, action.payload)
  end
  
  test "converts JSON payload keys to symbols recursively" do
    decision_source = lambda do |_visible_state|
      {
        "type" => "move",
        "payload" => {
          "from" => [1, 1],
          "to" => [1, 2],
          "metadata" => {
            "target_id" => 42
          }
        }
      }
    end

    action = DecisionProviders::AI.new(
      context: build_context,
      decision_source: decision_source
    ).call

    assert_equal [1, 1], action.payload[:from]
    assert_equal [1, 2], action.payload[:to]
    assert_equal 42, action.payload[:metadata][:target_id]
  end

  test "does not allow decision source to choose another player" do
    context = build_context

    decision_source = lambda do |_visible_state|
      {
        "type" => "end_turn",
        "payload" => {},
        "player_id" => "2"
      }
    end

    action = DecisionProviders::AI.new(
      context: context,
      decision_source: decision_source
    ).call

    assert_equal "1", action.player_id
  end
  
  test "does not expose opponent hand to decision source" do
    context = build_context

    decision_source = lambda do |visible_state|
      opponent = visible_state.fetch("players").fetch("2")

      assert opponent.key?("hand_count")
      refute opponent.key?("hand")

      {
        "type" => "end_turn",
        "payload" => {}
      }
    end

    action = DecisionProviders::AI.new(
      context: context,
      decision_source: decision_source
    ).call

    assert_equal "1", action.player_id
    assert_equal "end_turn", action.type
  end

  test "retries when decision source returns an invalid response" do
    context = build_context
    responses = [
      "invalid response",
      { "payload" => {} },
      {
        "type" => "end_turn",
        "payload" => {}
      }
    ]

    attempts = 0

    decision_source = lambda do |_visible_state|
      attempts += 1
      responses.shift
    end

    action = DecisionProviders::AI.new(
      context: context,
      decision_source: decision_source
    ).call

    assert_equal 3, attempts
    assert_instance_of GameEngine::Action, action
    assert_equal "1", action.player_id
    assert_equal "end_turn", action.type
  end

  test "raises an error after three invalid decisions" do
    attempts = 0

    decision_source = lambda do |_visible_state|
      attempts += 1
      "invalid response"
    end

    provider = DecisionProviders::AI.new(
      context: build_context,
      decision_source: decision_source
    )

    error = assert_raises(ArgumentError) do
      provider.call
    end

    assert_equal 3, attempts

    assert_includes(
      error.message,
      "AI failed to produce a valid decision after 3 attempts"
    )
  end
  
  test "does not retry when decision source raises an unexpected error" do
    attempts = 0

    decision_source = lambda do |_visible_state|
      attempts += 1
      raise "External AI API is unavailable"
    end

    provider = DecisionProviders::AI.new(
      context: build_context,
      decision_source: decision_source
    )

    error = assert_raises(RuntimeError) do
      provider.call
    end

    assert_equal "External AI API is unavailable", error.message
    assert_equal 1, attempts
  end

  test "rejects a non-hash decision" do
    provider = DecisionProviders::AI.new(
      context: build_context,
      decision_source: ->(_state) { "end_turn" }
    )

    assert_raises(ArgumentError) do
      provider.call
    end
  end

  test "rejects a decision without an action type" do
    provider = DecisionProviders::AI.new(
      context: build_context,
      decision_source: ->(_state) { { "payload" => {} } }
    )

    assert_raises(ArgumentError) do
      provider.call
    end
  end

  test "rejects a non-hash payload" do
    provider = DecisionProviders::AI.new(
      context: build_context,
      decision_source: lambda do |_state|
        {
          "type" => "move",
          "payload" => "invalid"
        }
      end
    )

    assert_raises(ArgumentError) do
      provider.call
    end
  end

  private

  def build_context
    DecisionProviders::Context.new(
      state: {
        "status" => "started",
        "turn_number" => 1,
        "current_player_id" => "1",
        "field" => Array.new(3) { Array.new(5) },
        "result" => nil,
        "players" => {
          "1" => build_player(
            hand: [
              {
                "card_id" => "own-card",
                "card_type" => "technique",
                "price" => 1
              }
            ]
          ),
          "2" => build_player(
            hand: [
              {
                "card_id" => "hidden-card",
                "card_type" => "technique",
                "price" => 1
              }
            ]
          )
        }
      },
      player_id: "1"
    )
  end

  def build_player(hand:)
    {
      "nation_id" => 1,
      "hand" => hand,
      "deck" => [],
      "platoons" => [nil, nil, nil],
      "resources" => 0,
      "remaining_time" => 600,
      "empty_deck_draw_attempts" => 0,
      "graveyard" => []
    }
  end
end
