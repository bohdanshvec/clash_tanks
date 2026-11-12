
require "test_helper"

class DecisionProviders::OpponentEngine::Planning::StrategicEvaluatorTest <
  ActiveSupport::TestCase

  setup do
    @ai_player_id = "42"
    @opponent_id = "57"

    @state = GameEngine::GameState.initial(
      current_player_id: 42,
      participants: [
        headquarters_participant(
          player_id: 42,
          nation_id: 10
        ),
        headquarters_participant(
          player_id: 57,
          nation_id: 20
        )
      ]
    )
  end

  test "returns a numeric and repeatable score" do
    visible_state = visible_state_for_ai
    original_state = visible_state.deep_dup

    first_score = evaluate(visible_state)
    second_score = evaluate(visible_state)

    assert_kind_of Numeric, first_score
    assert_equal first_score, second_score
    assert_equal original_state, visible_state
  end

  test "values own headquarters health" do
    visible_state = visible_state_for_ai
    damaged_state = visible_state.deep_dup

    damaged_state["field"][2][0]["hp"] = 10

    assert_operator(
      evaluate(visible_state),
      :>,
      evaluate(damaged_state)
    )
  end

  test "values damage dealt to enemy headquarters" do
    visible_state = visible_state_for_ai
    damaged_state = visible_state.deep_dup

    damaged_state["field"][0][4]["hp"] = 10

    assert_operator(
      evaluate(damaged_state),
      :>,
      evaluate(visible_state)
    )
  end

  test "values own techniques and platoons" do
    baseline_score = evaluate(visible_state_for_ai)

    @state["field"][1][1] = {
      "type" => "technique",
      "card_id" => 15,
      "player_id" => 42,
      "technique_type" => "medium_tank",
      "hp" => 10,
      "firepower" => 4,
      "fuel" => 2,
      "attack_range" => 1,
      "movement_count" => 1,
      "has_attacked" => false
    }

    @state["players"]["42"]["platoons"][0] = {
      "type" => "platoon",
      "card_id" => 16,
      "player_id" => 42,
      "hp" => 8,
      "firepower" => 3,
      "armor" => 2,
      "fuel" => 1
    }

    assert_operator(
      evaluate(visible_state_for_ai),
      :>,
      baseline_score
    )
  end

  test "values techniques positioned closer to enemy headquarters" do
    far_state = @state.deep_dup
    near_state = @state.deep_dup

    far_state["field"][1][1] = test_technique(42)
    near_state["field"][0][3] = test_technique(42)

    assert_operator(
      evaluate(state: near_state),
      :>,
      evaluate(state: far_state)
    )
  end

  test "penalizes enemy techniques positioned near own headquarters" do
    safe_state = @state.deep_dup
    threatened_state = @state.deep_dup

    safe_state["field"][0][3] = test_technique(57)
    threatened_state["field"][2][1] = test_technique(57)

    assert_operator(
      evaluate(state: safe_state),
      :>,
      evaluate(state: threatened_state)
    )
  end

  test "values available attacks" do
    @state["field"][1][1] = test_technique(42)
    @state["field"][1][2] = test_technique(57)

    ready_state = visible_state_for_ai

    @state["field"][1][1]["has_attacked"] = true

    spent_state = visible_state_for_ai

    assert_operator(
      evaluate(ready_state),
      :>,
      evaluate(spent_state)
    )
  end

  test "returns a dominant score for a finished game" do
    visible_state = visible_state_for_ai

    visible_state["status"] = "finished"
    visible_state["result"] = {
      "winner_id" => 42,
      "loser_id" => 57,
      "reason" => "headquarters_destroyed"
    }

    assert_equal(
      DecisionProviders::OpponentEngine::Planning::StrategicEvaluator::WIN_SCORE,
      evaluate(visible_state)
    )
  end

  test "returns a dominant negative score after defeat" do
    visible_state = visible_state_for_ai

    visible_state["status"] = "finished"
    visible_state["result"] = {
      "winner_id" => 57,
      "loser_id" => 42,
      "reason" => "headquarters_destroyed"
    }

    assert_equal(
      -DecisionProviders::OpponentEngine::Planning::StrategicEvaluator::WIN_SCORE,
      evaluate(visible_state)
    )
  end

  private

  def visible_state_for_ai
    GameEngine::VisibleState.call(
      state: @state,
      player_id: @ai_player_id
    )
  end

  def evaluate(visible_state = nil, state: nil)
    visible_state ||= GameEngine::VisibleState.call(
      state: state || @state,
      player_id: @ai_player_id
    )

    DecisionProviders::OpponentEngine::Planning::StrategicEvaluator.call(
      visible_state: visible_state,
      player_id: @ai_player_id
    )
  end

  def test_technique(player_id)
    {
      "type" => "technique",
      "card_id" => 15,
      "player_id" => player_id,
      "technique_type" => "medium_tank",
      "hp" => 10,
      "firepower" => 4,
      "fuel" => 2,
      "attack_range" => 1,
      "movement_count" => 1,
      "movement_limit" => 1,
      "movement_type" => "diagonal",
      "has_attacked" => false,
      "has_counterattacked" => false
    }
  end
end
