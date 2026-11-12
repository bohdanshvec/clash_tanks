
require "test_helper"

class DecisionProviders::OpponentEngine::Planning::StateSimulatorTest <
  ActiveSupport::TestCase

  setup do
    @ai_player_id = "42"
    @opponent_id = "57"
    @current_time = Time.current.change(usec: 0)

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

    @state["turn_started_at"] = @current_time.iso8601

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
      "movement_limit" => 1,
      "movement_type" => "diagonal",
      "has_attacked" => false,
      "has_counterattacked" => false
    }

    # Реальные скрытые данные нужны только исходной партии.
    # Симулятор не должен получить их содержимое.
    @state["players"]["57"]["hand"] = [
      {
        "card_id" => 9001,
        "name" => "OPPONENT_SECRET_HAND_CARD",
        "card_type" => "technique"
      }
    ]

    @state["players"]["57"]["deck"] = [
      {
        "card_id" => 9002,
        "name" => "OPPONENT_SECRET_DECK_CARD",
        "card_type" => "order"
      }
    ]

    @state["players"]["57"]["graveyard"] = [
      {
        "card_id" => 9003,
        "name" => "OPPONENT_SECRET_GRAVEYARD_CARD",
        "card_type" => "platoon"
      }
    ]
  end

  test "simulates a move using GameEngine without mutating visible state" do
    visible_state = visible_state_for_ai
    original_visible_state = visible_state.deep_dup

    result = simulate(
      visible_state,
      {
        "type" => "move",
        "payload" => {
          "from" => [1, 1],
          "to" => [0, 2]
        }
      }
    )

    assert result.success?, result.error

    assert_nil result.visible_state.dig("field", 1, 1)
    assert_equal(
      "technique",
      result.visible_state.dig("field", 0, 2, "type")
    )

    assert_equal original_visible_state, visible_state

    # Полный simulation state не возвращается.
    refute result.respond_to?(:state)
  end

  test "uses hidden placeholders when simulating the opponent's card draw" do
    visible_state = visible_state_for_ai

    result = simulate(
      visible_state,
      {
        "type" => "end_turn",
        "payload" => {}
      }
    )

    assert result.success?, result.error

    simulated_opponent = result.visible_state.dig("players", @opponent_id)

    assert_equal 2, simulated_opponent["hand_count"]
    assert_equal 0, simulated_opponent["deck_count"]

    assert_equal(
      "card_drawn",
      result.events.last[:type]
    )

    serialized_result = result.visible_state.to_s

    refute_includes serialized_result, "OPPONENT_SECRET_HAND_CARD"
    refute_includes serialized_result, "OPPONENT_SECRET_DECK_CARD"
    refute_includes serialized_result, "OPPONENT_SECRET_GRAVEYARD_CARD"

    refute result.respond_to?(:state)
  end

  test "does not mutate the original visible state" do
    visible_state = visible_state_for_ai
    original_visible_state = visible_state.deep_dup

    simulate(
      visible_state,
      {
        "type" => "move",
        "payload" => {
          "from" => [1, 1],
          "to" => [0, 2]
        }
      }
    )

    assert_equal original_visible_state, visible_state
  end

  test "returns failure when GameEngine rejects an action" do
    visible_state = visible_state_for_ai

    result = simulate(
      visible_state,
      {
        "type" => "unknown_action",
        "payload" => {}
      }
    )

    assert_not result.success?
    assert_equal "Unknown action type", result.error
    assert_nil result.visible_state
    assert_empty result.events
  end

  test "does not simulate actions during the opponent's turn" do
    visible_state = visible_state_for_ai
    visible_state["current_player_id"] = @opponent_id

    result = simulate(
      visible_state,
      {
        "type" => "end_turn",
        "payload" => {}
      }
    )

    assert_not result.success?
    assert_equal "It is not the AI player's turn", result.error
  end

  private

  def visible_state_for_ai
    GameEngine::VisibleState.call(
      state: @state,
      player_id: @ai_player_id
    )
  end

  def simulate(visible_state, action)
    DecisionProviders::OpponentEngine::Planning::StateSimulator.call(
      visible_state: visible_state,
      player_id: @ai_player_id,
      action: action,
      current_time: @current_time
    )
  end
end
