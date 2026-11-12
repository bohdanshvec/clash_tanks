
require "test_helper"

class DecisionProvidersAITest < ActiveSupport::TestCase
  test "can initialize without an external AI provider or API key" do
    provider = DecisionProviders::AI.new(
      context: build_context
    )

    assert_instance_of DecisionProviders::AI, provider
  end

  test "uses the native opponent engine by default" do
    context = build_context

    action = DecisionProviders::AI.new(
      context: context
    ).call

    assert_instance_of GameEngine::Action, action
    assert_equal "1", action.player_id
    assert_equal context.state_digest, action.expected_state_digest
    assert_includes %w[move attack play_card end_turn], action.type
  end

  test "uses the native opponent engine regardless of legacy AI_PROVIDER value" do
    previous_provider = ENV["AI_PROVIDER"]
    ENV["AI_PROVIDER"] = "groq"

    begin
      context = build_context

      action = DecisionProviders::AI.new(
        context: context
      ).call

      assert_instance_of GameEngine::Action, action
      assert_equal "1", action.player_id
      assert_equal context.state_digest, action.expected_state_digest
    ensure
      if previous_provider.nil?
        ENV.delete("AI_PROVIDER")
      else
        ENV["AI_PROVIDER"] = previous_provider
      end
    end
  end

  test "returns the native opponent engine plan with its expected state" do
    context = build_context

    decision = DecisionProviders::AI.new(
      context: context
    ).call_with_plan

    assert_instance_of GameEngine::Action, decision.action

    assert_instance_of(
      DecisionProviders::OpponentEngine::Planning::TacticalPlanner::Result,
      decision.plan
    )

    assert_equal context.state_digest,
                 decision.action.expected_state_digest

    assert_equal(
      decision.plan.steps.first.expected_visible_state,
      decision.expected_visible_state
    )

    assert_equal 1, decision.next_step_index

    assert_equal(
      decision.plan.actions.first["type"],
      decision.action.type
    )
  end

  test "converts an injected decision into a game action" do
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

  test "converts injected JSON payload keys to symbols recursively" do
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

  test "does not allow injected decision source to choose another player" do
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

  test "does not expose opponent hand to injected decision source" do
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

  test "retries when injected decision source returns an invalid response" do
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
      context: build_context,
      decision_source: decision_source
    ).call

    assert_equal 3, attempts
    assert_instance_of GameEngine::Action, action
    assert_equal "1", action.player_id
    assert_equal "end_turn", action.type
  end

  test "raises an error after three invalid injected decisions" do
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

  test "does not retry when injected decision source raises an unexpected error" do
    attempts = 0

    decision_source = lambda do |_visible_state|
      attempts += 1
      raise "Injected decision source failed"
    end

    provider = DecisionProviders::AI.new(
      context: build_context,
      decision_source: decision_source
    )

    error = assert_raises(RuntimeError) do
      provider.call
    end

    assert_equal "Injected decision source failed", error.message
    assert_equal 1, attempts
  end

  test "rejects a non-hash injected decision" do
    provider = DecisionProviders::AI.new(
      context: build_context,
      decision_source: ->(_state) { "end_turn" }
    )

    assert_raises(ArgumentError) do
      provider.call
    end
  end

  test "rejects an injected decision without an action type" do
    provider = DecisionProviders::AI.new(
      context: build_context,
      decision_source: ->(_state) { { "payload" => {} } }
    )

    assert_raises(ArgumentError) do
      provider.call
    end
  end

  test "rejects a non-hash injected decision payload" do
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

  test "does not allow a prebuilt action to use another player" do
    context = build_context

    decision_source = lambda do |_visible_state|
      GameEngine::Action.new(
        player_id: "2",
        type: "end_turn",
        payload: {},
        expected_state_digest: context.state_digest
      )
    end

    assert_raises(ArgumentError) do
      DecisionProviders::AI.new(
        context: context,
        decision_source: decision_source
      ).call
    end
  end

  test "wraps injected decision source without creating a plan" do
    decision_source = lambda do |_visible_state|
      {
        "type" => "end_turn",
        "payload" => {}
      }
    end

    decision = DecisionProviders::AI.new(
      context: build_context,
      decision_source: decision_source
    ).call_with_plan

    assert_instance_of GameEngine::Action, decision.action
    assert_nil decision.plan
    assert_nil decision.expected_visible_state
    assert_nil decision.next_step_index
    assert_equal "end_turn", decision.action.type
  end

  private

  def build_context
    field = Array.new(3) { Array.new(5) }

    field[2][0] = {
      "type" => "headquarters",
      "card_id" => "1",
      "player_id" => "1",
      "nation_id" => 1,
      "name" => "Test HQ",
      "hp" => 20,
      "firepower" => 3,
      "fuel" => 5,
      "has_attacked" => false,
      "has_counterattacked" => false,
      "abilities" => []
    }

    field[0][4] = {
      "type" => "headquarters",
      "card_id" => "2",
      "player_id" => "2",
      "nation_id" => 2,
      "name" => "Test HQ",
      "hp" => 20,
      "firepower" => 3,
      "fuel" => 5,
      "has_attacked" => false,
      "has_counterattacked" => false,
      "abilities" => []
    }

    DecisionProviders::Context.new(
      state: {
        "status" => "started",
        "turn_number" => 1,
        "current_player_id" => "1",
        "turn_started_at" => Time.current.iso8601,
        "field" => field,
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
