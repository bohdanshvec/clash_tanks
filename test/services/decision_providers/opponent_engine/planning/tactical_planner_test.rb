
require "test_helper"

class DecisionProviders::OpponentEngine::Planning::TacticalPlannerTest <
  ActiveSupport::TestCase

  AI_PLAYER_ID = 42
  OPPONENT_ID = 57

  def setup
    @state = GameEngine::GameState.initial(
      current_player_id: AI_PLAYER_ID,
      participants: [
        headquarters_participant(
          player_id: AI_PLAYER_ID,
          nation_id: 10
        ),
        headquarters_participant(
          player_id: OPPONENT_ID,
          nation_id: 20
        )
      ]
    )

    add_headquarters_stats

    @current_time = Time.current + 1.second
  end

  test "returns a plan containing end turn when no other actions are available" do
    @state["field"][2][0]["has_attacked"] = true

    result = plan

    assert_equal 1, result.actions.length
    assert_equal "end_turn", result.actions.first["type"]
    assert_operator result.expanded_nodes, :>=, 1
  end

  test "chooses an attack that destroys an enemy technique" do
    @state["field"][2][0]["has_attacked"] = true

    @state["field"][1][1] = technique(
      player_id: AI_PLAYER_ID,
      hp: 10,
      firepower: 4
    )

    @state["field"][1][2] = technique(
      player_id: OPPONENT_ID,
      hp: 4,
      firepower: 3
    )

    result = plan

    assert_not_empty result.actions
    assert_equal "attack", result.actions.first["type"]

    assert_equal(
      [1, 1],
      result.actions.first.dig("payload", "attacker")
    )

    assert_equal(
      [1, 2],
      result.actions.first.dig("payload", "target")
    )
  end

  test "does not continue searching after end turn" do
    @state["field"][2][0]["has_attacked"] = true

    result = plan

    end_turn_index = result.actions.index do |action|
      action["type"] == "end_turn"
    end

    assert_equal(
      result.actions.length - 1,
      end_turn_index
    ) if end_turn_index
  end

  test "preserves expected visible state after every planned action" do
    visible_state = visible_state_for_ai
    result = plan(visible_state)

    assert_equal result.actions.length, result.steps.length
    refute_empty result.steps

    current_state = visible_state

    result.steps.each_with_index do |step, index|
      assert_equal result.actions[index], step.action

      simulation =
        DecisionProviders::OpponentEngine::Planning::StateSimulator.call(
          visible_state: current_state,
          player_id: AI_PLAYER_ID,
          action: step.action,
          current_time: @current_time
        )

      assert simulation.success?
      assert_equal simulation.visible_state, step.expected_visible_state

      current_state = step.expected_visible_state
    end
  end

  test "does not mutate the original visible state" do
    visible_state = visible_state_for_ai
    original_state = visible_state.deep_dup

    plan(visible_state)

    assert_equal original_state, visible_state
  end

  test "respects configured search depth" do
    @state["field"][2][0]["has_attacked"] = true

    result = plan(
      depth: 2,
      width: 3
    )

    assert_operator result.actions.length, :<=, 2
  end

  test "returns an empty plan when it is not the AI player's turn" do
    @state["current_player_id"] = OPPONENT_ID

    result = plan

    assert_empty result.actions
    assert_equal 0, result.expanded_nodes
  end

  test "rejects invalid search parameters" do
    assert_raises(ArgumentError) do
      plan(depth: 0)
    end

    assert_raises(ArgumentError) do
      plan(width: 0)
    end
  end

  private

  def plan(
    visible_state = nil,
    depth: DecisionProviders::OpponentEngine::Planning::TacticalPlanner::DEFAULT_DEPTH,
    width: DecisionProviders::OpponentEngine::Planning::TacticalPlanner::DEFAULT_WIDTH
  )
    visible_state ||= visible_state_for_ai

    DecisionProviders::OpponentEngine::Planning::TacticalPlanner.call(
      visible_state: visible_state,
      player_id: AI_PLAYER_ID,
      current_time: @current_time,
      depth: depth,
      width: width
    )
  end

  def visible_state_for_ai
    GameEngine::VisibleState.call(
      state: @state,
      player_id: AI_PLAYER_ID
    )
  end

  def add_headquarters_stats
    [@state["field"][2][0], @state["field"][0][4]].each do |headquarters|
      headquarters.merge!(
        "hp" => 20,
        "firepower" => 4,
        "fuel" => 5,
        "has_attacked" => false,
        "has_counterattacked" => false
      )
    end
  end

  def technique(player_id:, hp:, firepower:)
    {
      "type" => "technique",
      "card_id" => 15,
      "player_id" => player_id,
      "technique_type" => "medium_tank",
      "hp" => hp,
      "firepower" => firepower,
      "fuel" => 2,
      "attack_range" => 1,
      "movement_count" => 0,
      "movement_limit" => 1,
      "movement_type" => "diagonal",
      "has_attacked" => false,
      "has_counterattacked" => false
    }
  end
end
