require "test_helper"

class GameActionRunnerTest < ActiveSupport::TestCase
  setup do
    @player = create_player
    @enemy = create_player

    @nation = create_nation("runner_test_nation")
    @enemy_nation = create_nation("runner_test_enemy_nation")

    @state = GameEngine::GameState.initial(
      current_player_id: @player.id,
      participants: [
        headquarters_participant(
          player_id: @player.id,
          nation_id: @nation.id
        ),
        headquarters_participant(
          player_id: @enemy.id,
          nation_id: @enemy_nation.id
        )
      ]
    )

    @state["current_player_id"] = @player.id.to_s

    @game = Game.create!(
      status: "started",
      state: @state
    )
  end

  test "saves state after a successful action" do
    action = GameEngine::Action.new(
      player_id: @player.id.to_s,
      type: "end_turn"
    )

    result = GameActionRunner.call(
      game: @game,
      action: action
    )

    assert_predicate result, :success?
    assert_nil result.error

    @game.reload

    assert_equal result.state, @game.state
    assert_kind_of Array, result.events
  end

  test "does not save state after a rejected action" do
    original_state = @game.state.deep_dup

    action = GameEngine::Action.new(
      player_id: @player.id.to_s,
      type: "move",
      payload: {
        from: [1, 1],
        to: [1, 2]
      }
    )

    result = GameActionRunner.call(
      game: @game,
      action: action
    )

    refute_predicate result, :success?
    assert_not_nil result.error

    @game.reload

    assert_equal original_state, @game.state
  end

  test "rejects an action when the game has not started" do
    @game.update!(
      status: "waiting",
      state: nil
    )

    action = GameEngine::Action.new(
      player_id: @player.id.to_s,
      type: "end_turn"
    )

    result = GameActionRunner.call(
      game: @game,
      action: action
    )

    refute_predicate result, :success?
    assert_equal "Game has not started", result.error
    assert_nil result.state
    assert_empty result.events

    @game.reload

    assert @game.waiting?
    assert_nil @game.state
  end
  
  test "rejects an AI action when the state changed after the decision" do
    original_digest = GameEngine::StateDigest.call(@game.state)

    action = GameEngine::Action.new(
      player_id: @player.id.to_s,
      type: "end_turn",
      expected_state_digest: original_digest
    )

    changed_state = @game.state.deep_dup
    changed_state["turn_number"] += 1

    @game.update!(state: changed_state)
    state_before_action = @game.reload.state.deep_dup

    result = GameActionRunner.call(
      game: @game,
      action: action
    )

    refute_predicate result, :success?
    assert_equal GameActionRunner::STALE_STATE_ERROR, result.error
    assert_nil result.state
    assert_empty result.events

    assert_equal state_before_action, @game.reload.state
  end

  test "accepts an AI action when the state has not changed" do
    digest = GameEngine::StateDigest.call(@game.state)

    action = GameEngine::Action.new(
      player_id: @player.id.to_s,
      type: "end_turn",
      expected_state_digest: digest
    )

    result = GameActionRunner.call(
      game: @game,
      action: action
    )

    assert_predicate result, :success?
    assert_nil result.error
    assert_equal result.state, @game.reload.state
  end

  private

  def create_nation(code)
    Nation.create!(
      name: code.humanize,
      code: code
    )
  end
end
