require "test_helper"

class DecisionProvidersOpponentEngineActionExecutorTest < ActiveSupport::TestCase
  test "converts the first planned action into a game action" do
    context = build_context

    plan = Struct.new(:actions).new(
      [
        {
          "type" => "move",
          "payload" => {
            "from" => [1, 1],
            "to" => [1, 2]
          }
        },
        {
          "type" => "end_turn",
          "payload" => {}
        }
      ]
    )

    action = DecisionProviders::OpponentEngine::ActionExecutor.call(
      plan: plan,
      context: context
    )

    assert_instance_of GameEngine::Action, action
    assert_equal "1", action.player_id
    assert_equal "move", action.type
    assert_equal [1, 1], action.payload[:from]
    assert_equal [1, 2], action.payload[:to]
    assert_equal context.state_digest, action.expected_state_digest
  end

  test "normalizes nested payload keys" do
    context = build_context

    plan = Struct.new(:actions).new(
      [
        {
          "type" => "move",
          "payload" => {
            "metadata" => {
              "target_id" => 42
            }
          }
        }
      ]
    )

    action = DecisionProviders::OpponentEngine::ActionExecutor.call(
      plan: plan,
      context: context
    )

    assert_equal 42, action.payload[:metadata][:target_id]
  end

  test "rejects an empty plan" do
    plan = Struct.new(:actions).new([])

    assert_raises(
      DecisionProviders::OpponentEngine::ActionExecutor::InvalidPlan
    ) do
      DecisionProviders::OpponentEngine::ActionExecutor.call(
        plan: plan,
        context: build_context
      )
    end
  end

  test "rejects an invalid planned action" do
    plan = Struct.new(:actions).new(["invalid"])

    assert_raises(
      DecisionProviders::OpponentEngine::ActionExecutor::InvalidPlan
    ) do
      DecisionProviders::OpponentEngine::ActionExecutor.call(
        plan: plan,
        context: build_context
      )
    end
  end

  test "executes the first plan step and returns its expected state" do
    context = build_context
    expected_state = { "turn_number" => 1, "field" => [] }

    first_action = {
      "type" => "move",
      "payload" => {
        "from" => [1, 1],
        "to" => [1, 2]
      }
    }

    second_action = {
      "type" => "end_turn",
      "payload" => {}
    }

    plan = build_plan(
      actions: [first_action, second_action],
      expected_states: [
        expected_state,
        { "turn_number" => 1, "field" => [] }
      ]
    )

    execution =
      DecisionProviders::OpponentEngine::ActionExecutor.execute(
        plan: plan,
        context: context
      )

    assert_instance_of GameEngine::Action, execution.action
    assert_equal "move", execution.action.type
    assert_equal context.state_digest, execution.action.expected_state_digest
    assert_equal expected_state, execution.expected_visible_state
    assert_equal 1, execution.next_step_index
  end

  test "executes the requested plan step" do
    context = build_context

    first_action = {
      "type" => "move",
      "payload" => {}
    }

    second_action = {
      "type" => "end_turn",
      "payload" => {}
    }

    expected_state = {
      "turn_number" => 2,
      "current_player_id" => "1"
    }

    plan = build_plan(
      actions: [first_action, second_action],
      expected_states: [
        { "turn_number" => 1 },
        expected_state
      ]
    )

    execution =
      DecisionProviders::OpponentEngine::ActionExecutor.execute(
        plan: plan,
        context: context,
        step_index: 1
      )

    assert_equal "end_turn", execution.action.type
    assert_equal expected_state, execution.expected_visible_state
    assert_equal 2, execution.next_step_index
  end

  test "rejects a plan with different action and step counts" do
    plan = build_plan(
      actions: [
        { "type" => "end_turn", "payload" => {} }
      ],
      expected_states: []
    )

    assert_raises(
      DecisionProviders::OpponentEngine::ActionExecutor::InvalidPlan
    ) do
      DecisionProviders::OpponentEngine::ActionExecutor.execute(
        plan: plan,
        context: build_context
      )
    end
  end

  test "rejects a plan step outside the plan" do
    plan = build_plan(
      actions: [
        { "type" => "end_turn", "payload" => {} }
      ],
      expected_states: [
        { "turn_number" => 1 }
      ]
    )

    assert_raises(
      DecisionProviders::OpponentEngine::ActionExecutor::InvalidPlan
    ) do
      DecisionProviders::OpponentEngine::ActionExecutor.execute(
        plan: plan,
        context: build_context,
        step_index: 1
      )
    end
  end

  test "rejects a negative plan step index" do
    plan = build_plan(
      actions: [
        { "type" => "end_turn", "payload" => {} }
      ],
      expected_states: [
        { "turn_number" => 1 }
      ]
    )

    assert_raises(
      DecisionProviders::OpponentEngine::ActionExecutor::InvalidPlan
    ) do
      DecisionProviders::OpponentEngine::ActionExecutor.execute(
        plan: plan,
        context: build_context,
        step_index: -1
      )
    end
  end

  private

  def build_plan(actions:, expected_states:)
    step_class = Struct.new(:action, :expected_visible_state)

    Struct.new(:actions, :steps).new(
      actions,
      actions.each_with_index.map do |action, index|
        step_class.new(action, expected_states[index])
      end
    )
  end

  def build_context
    DecisionProviders::Context.new(
      state: {
        "status" => "started",
        "turn_number" => 1,
        "current_player_id" => "1",
        "field" => Array.new(3) { Array.new(5) },
        "result" => nil,
        "players" => {
          "1" => build_player,
          "2" => build_player
        }
      },
      player_id: "1"
    )
  end

  def build_player
    {
      "nation_id" => 1,
      "hand" => [],
      "deck" => [],
      "platoons" => [nil, nil, nil],
      "resources" => 0,
      "remaining_time" => 600,
      "empty_deck_draw_attempts" => 0,
      "graveyard" => []
    }
  end
end