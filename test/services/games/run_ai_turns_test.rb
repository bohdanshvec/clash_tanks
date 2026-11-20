
require "test_helper"
require "timeout"

class Games::RunAiTurnsTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @games = []
    @players = []
    @nations = []

    @game, @ai_player, @human_player = create_ai_game
  end

  teardown do
    @games.each(&:destroy!)
    @players.each(&:destroy!)
    @nations.each(&:destroy!)
  end

  test "does not run AI actions concurrently for the same game" do
    decision_started = Queue.new
    release_decision = Queue.new
    first_result = Queue.new

    decision_source = lambda do |_visible_state|
      decision_started << true
      release_decision.pop

      {
        "type" => "end_turn",
        "payload" => {}
      }
    end

    worker = Thread.new do
      first_result << Games::RunAiTurns.call(
        game: @game,
        decision_source: decision_source
      )
    end

    begin
      Timeout.timeout(10) do
        decision_started.pop
      end

      second_decision_called = false

      second_result = Games::RunAiTurns.call(
        game: @game,
        decision_source: lambda do |_visible_state|
          second_decision_called = true

          {
            "type" => "end_turn",
            "payload" => {}
          }
        end
      )

      assert second_result.success?, second_result.error
      assert_equal 0, second_result.actions_count
      assert_not second_decision_called
    ensure
      release_decision << true
      worker.join(10)

      if worker.alive?
        worker.kill
        worker.join
        flunk "Первый запуск ИИ не завершился за 10 секунд"
      end
    end

    result = first_result.pop

    assert result.success?, result.error
    assert_equal 1, result.actions_count
  end

  test "allows AI turns for different games to run independently" do
    another_game, = create_ai_game

    decision_started = Queue.new
    release_decision = Queue.new
    first_result = Queue.new

    decision_source = lambda do |_visible_state|
      decision_started << true
      release_decision.pop

      {
        "type" => "end_turn",
        "payload" => {}
      }
    end

    worker = Thread.new do
      first_result << Games::RunAiTurns.call(
        game: @game,
        decision_source: decision_source
      )
    end

    begin
      Timeout.timeout(10) do
        decision_started.pop
      end

      second_result = Games::RunAiTurns.call(
        game: another_game,
        decision_source: lambda do |_visible_state|
          {
            "type" => "end_turn",
            "payload" => {}
          }
        end
      )

      assert second_result.success?, second_result.error
      assert_equal 1, second_result.actions_count
    ensure
      release_decision << true
      worker.join(10)

      if worker.alive?
        worker.kill
        worker.join
        flunk "Первый запуск ИИ не завершился за 10 секунд"
      end
    end

    result = first_result.pop

    assert result.success?, result.error
    assert_equal 1, result.actions_count
  end

  test "releases the advisory lock after a decision error" do
    failed_result = Games::RunAiTurns.call(
      game: @game,
      decision_source: lambda do |_visible_state|
        raise "Simulated decision failure"
      end
    )

    assert_not failed_result.success?
    assert_equal 0, failed_result.actions_count

    retry_result = Games::RunAiTurns.call(
      game: @game,
      decision_source: lambda do |_visible_state|
        {
          "type" => "end_turn",
          "payload" => {}
        }
      end
    )

    assert retry_result.success?, retry_result.error
    assert_equal 1, retry_result.actions_count
  end

  test "releases the advisory lock after a successful AI turn" do
    first_result = Games::RunAiTurns.call(
      game: @game,
      decision_source: lambda do |_visible_state|
        {
          "type" => "end_turn",
          "payload" => {}
        }
      end
    )

    assert first_result.success?, first_result.error
    assert_equal 1, first_result.actions_count

    state = @game.reload.state.deep_dup
    state["current_player_id"] = @ai_player.id.to_s
    @game.update!(state: state)

    second_result = Games::RunAiTurns.call(
      game: @game,
      decision_source: lambda do |_visible_state|
        {
          "type" => "end_turn",
          "payload" => {}
        }
      end
    )

    assert second_result.success?, second_result.error
    assert_equal 1, second_result.actions_count
  end

  test "preserves successful AI action events when the next decision fails" do
    calls = 0
    callback_events = []
    callback_states = []

    decision_source = lambda do |_visible_state|
      calls += 1

      if calls == 1
        {
          "type" => "attack",
          "payload" => {
            "attacker" => [2, 0],
            "target" => [0, 4]
          }
        }
      else
        raise "Simulated decision failure after successful action"
      end
    end

    initial_state = @game.reload.state.deep_dup
    human_hq_initial_hp = initial_state.dig(
      "field", 0, 4, "hp"
    )

    result = Games::RunAiTurns.call(
      game: @game,
      decision_source: decision_source,
      on_action: lambda do |action_events|
        callback_events << action_events
        callback_states << @game.reload.state.deep_dup
      end
    )

    assert_not result.success?
    assert_equal 1, result.actions_count
    assert_equal 2, calls

    assert_equal(
      [
        "headquarters_attacked",
        "shot_fired",
        "damage_applied"
      ],
      result.events.map { |event| event[:type] }
    )

    attack_event = result.events.first

    assert_equal [2, 0], attack_event.dig(:attacker, :position)
    assert_equal [0, 4], attack_event.dig(:target, :position)

    assert_equal 1, callback_events.size
    assert_equal result.events, callback_events.first

    assert_equal 1, callback_states.size

    callback_hq = callback_states.first.dig(
      "field", 0, 4
    )

    assert_operator callback_hq["hp"], :<, human_hq_initial_hp

    @game.reload

    assert @game.started?

    assert_equal(
      @ai_player.id.to_s,
      @game.state["current_player_id"].to_s
    )

    human_hq = @game.state.dig("field", 0, 4)

    assert_operator human_hq["hp"], :<, human_hq_initial_hp
  end

  test "does not execute actions when the action limit is zero" do
    decision_called = false

    result = Games::RunAiTurns.call(
      game: @game,
      max_actions: 0,
      decision_source: lambda do |_visible_state|
        decision_called = true

        {
          "type" => "end_turn",
          "payload" => {}
        }
      end
    )

    assert_not result.success?
    assert_equal 0, result.actions_count
    assert_not decision_called

    @game.reload

    assert @game.started?

    assert_equal(
      @ai_player.id.to_s,
      @game.state["current_player_id"].to_s
    )
  end

  test "releases the advisory lock after an invalid action" do
    failed_result = Games::RunAiTurns.call(
      game: @game,
      decision_source: lambda do |_visible_state|
        {
          "type" => "invalid_action",
          "payload" => {}
        }
      end
    )

    assert_not failed_result.success?
    assert_equal 0, failed_result.actions_count

    retry_result = Games::RunAiTurns.call(
      game: @game,
      decision_source: lambda do |_visible_state|
        {
          "type" => "end_turn",
          "payload" => {}
        }
      end
    )

    assert retry_result.success?, retry_result.error
    assert_equal 1, retry_result.actions_count
  end

  test "retries a decision when the game state becomes stale" do
    calls = 0

    result = Games::RunAiTurns.call(
      game: @game,
      decision_source: lambda do |_visible_state|
        calls += 1

        if calls == 1
          state = @game.reload.state.deep_dup
          state["turn_number"] += 1
          @game.update!(state: state)
        end

        {
          "type" => "end_turn",
          "payload" => {}
        }
      end
    )

    assert result.success?, result.error
    assert_equal 2, calls
    assert_equal 1, result.actions_count

    @game.reload

    assert_equal(
      @human_player.id.to_s,
      @game.state["current_player_id"].to_s
    )
  end

  test "stops after exhausting stale state retries" do
    calls = 0

    result = Games::RunAiTurns.call(
      game: @game,
      decision_source: lambda do |_visible_state|
        calls += 1

        state = @game.reload.state.deep_dup
        state["turn_number"] += 1
        @game.update!(state: state)

        {
          "type" => "end_turn",
          "payload" => {}
        }
      end
    )

    assert_not result.success?
    assert_includes result.error, "3 повторов"
    assert_equal 4, calls
    assert_equal 0, result.actions_count

    @game.reload

    assert @game.started?

    assert_equal(
      @ai_player.id.to_s,
      @game.state["current_player_id"].to_s
    )
  end

  test "stops when the game finishes during a decision" do
    calls = 0

    result = Games::RunAiTurns.call(
      game: @game,
      decision_source: lambda do |_visible_state|
        calls += 1

        state = @game.reload.state.deep_dup
        state["turn_number"] += 1

        @game.update!(
          status: "finished",
          state: state
        )

        {
          "type" => "end_turn",
          "payload" => {}
        }
      end
    )

    assert result.success?, result.error
    assert_equal 1, calls
    assert_equal 0, result.actions_count

    @game.reload

    assert @game.finished?
  end

  test "stops when the turn passes to a human during a decision" do
    calls = 0

    result = Games::RunAiTurns.call(
      game: @game,
      decision_source: lambda do |_visible_state|
        calls += 1

        state = @game.reload.state.deep_dup
        state["current_player_id"] = @human_player.id.to_s
        @game.update!(state: state)

        {
          "type" => "end_turn",
          "payload" => {}
        }
      end
    )

    assert result.success?, result.error
    assert_equal 1, calls
    assert_equal 0, result.actions_count

    @game.reload

    assert_equal(
      @human_player.id.to_s,
      @game.state["current_player_id"].to_s
    )
  end

  test "waits between successful AI actions while the AI turn continues" do
    calls = 0
    delays = []
    broadcasts = []

    result = Games::RunAiTurns.call(
      game: @game,
      decision_source: lambda do |_visible_state|
        calls += 1

        if calls == 1
          {
            "type" => "attack",
            "payload" => {
              "attacker" => [2, 0],
              "target" => [0, 4]
            }
          }
        else
          {
            "type" => "end_turn",
            "payload" => {}
          }
        end
      end,
      on_action: lambda do |events|
        broadcasts << events
      end,
      sleeper: lambda do |seconds|
        delays << seconds
      end
    )

    assert result.success?, result.error
    assert_equal 2, result.actions_count
    assert_equal 2, broadcasts.size

    assert_equal [2.5], delays
  end

  test "reuses the opponent plan when the state matches and the next action is legal" do
    context = DecisionProviders::Context.new(
      state: @game.reload.state,
      player_id: @ai_player.id.to_s
    )

    legal_action = DecisionProviders::ActionOptions.call(
      context.visible_state
    ).first

    assert legal_action, "Expected at least one legal AI action"

    prepare_opponent_plan(
      context: context,
      action: legal_action
    )

    assert service_reuses_opponent_plan?(context)
  end

  test "does not reuse the opponent plan when the visible state changes" do
    context = DecisionProviders::Context.new(
      state: @game.reload.state,
      player_id: @ai_player.id.to_s
    )

    legal_action = DecisionProviders::ActionOptions.call(
      context.visible_state
    ).first

    assert legal_action, "Expected at least one legal AI action"

    prepare_opponent_plan(
      context: context,
      action: legal_action
    )

    changed_state = @game.reload.state.deep_dup
    changed_state["turn_number"] += 1

    changed_context = DecisionProviders::Context.new(
      state: changed_state,
      player_id: @ai_player.id.to_s
    )

    assert_not service_reuses_opponent_plan?(changed_context)
  end

  test "does not reuse the opponent plan when its next action is no longer legal" do
    context = DecisionProviders::Context.new(
      state: @game.reload.state,
      player_id: @ai_player.id.to_s
    )

    illegal_action = {
      "type" => "__invalid_opponent_plan_action__",
      "payload" => {}
    }

    prepare_opponent_plan(
      context: context,
      action: illegal_action
    )

    assert_not service_reuses_opponent_plan?(context)
  end

  test "native opponent engine reuses a plan to play two platoons" do
    prepare_native_engine_ai_hand

    planner = DecisionProviders::OpponentEngine::Planning::TacticalPlanner
    original_call = planner.method(:call)
    planner_calls = 0

    planner.singleton_class.define_method(:call) do |**kwargs|
      planner_calls += 1
      original_call.call(**kwargs)
    end

    begin
      result = Games::RunAiTurns.call(
        game: @game,
        sleeper: ->(_seconds) {}
      )
    ensure
      planner.singleton_class.define_method(:call, original_call)
    end

    assert result.success?, result.error.inspect

    final_state = @game.reload.state
    ai_state = final_state.fetch("players").fetch(@ai_player.id.to_s)

    assert_equal 2, ai_state.fetch("platoons").compact.length
    assert_empty ai_state.fetch("hand")
    assert_equal 0, ai_state.fetch("resources")

    platoon_events = result.events.count do |event|
      (event[:type] || event["type"]).to_s == "platoon_played"
    end

    assert_equal 2, platoon_events
    assert_equal 4, result.actions_count

    assert_equal 1, planner_calls
  end

  private

  def prepare_native_engine_ai_hand
    state = @game.state.deep_dup
    ai_state = state.fetch("players").fetch(@ai_player.id.to_s)

    ai_state["resources"] = 4
    ai_state["hand"] = [
      native_engine_platoon_card(
        card_id: 40,
        nation_id: ai_state.fetch("nation_id")
      ),
      native_engine_platoon_card(
        card_id: 41,
        nation_id: ai_state.fetch("nation_id")
      )
    ]

    @game.update!(state: state)
  end

  def native_engine_platoon_card(card_id:, nation_id:)
    {
      "card_id" => card_id,
      "name" => "Пехотный взвод #{card_id}",
      "card_type" => "platoon",
      "nation_id" => nation_id,
      "weight" => 1,
      "price" => 2,
      "platoon" => {
        "firepower" => 5,
        "hp" => 10,
        "armor" => 3,
        "fuel" => 2
      }
    }
  end

  def prepare_opponent_plan(context:, action:)
    service = Games::RunAiTurns.new(
      game: @game,
      max_actions: 20
    )

    plan = Struct.new(:actions).new([action])

    service.instance_variable_set(:@opponent_plan, plan)
    service.instance_variable_set(
      :@opponent_plan_expected_visible_state,
      context.visible_state
    )
    service.instance_variable_set(:@opponent_plan_step_index, 0)
    service.instance_variable_set(
      :@opponent_plan_player_id,
      @ai_player.id.to_s
    )

    @plan_test_service = service
  end

  def service_reuses_opponent_plan?(context)
    @plan_test_service.send(
      :reusable_opponent_plan_step?,
      context: context,
      current_player_id: @ai_player.id.to_s
    )
  end

  def create_ai_game
    ai_player = @ai_player

    unless ai_player
      ai_player = create_player(
        name: "AI #{SecureRandom.hex(4)}",
        email: "ai-#{SecureRandom.hex(8)}@example.com"
      )

      ai_player.update!(ai: true)
      @ai_player = ai_player
      @players << ai_player
    end

    human_player = create_player(
      name: "Human #{SecureRandom.hex(4)}",
      email: "human-#{SecureRandom.hex(8)}@example.com"
    )

    ai_nation = create_nation("ai_#{SecureRandom.hex(4)}")
    human_nation = create_nation("human_#{SecureRandom.hex(4)}")

    state = GameEngine::GameState.initial(
      current_player_id: ai_player.id,
      participants: [
        headquarters_participant(
          player_id: ai_player.id,
          nation_id: ai_nation.id
        ),
        headquarters_participant(
          player_id: human_player.id,
          nation_id: human_nation.id
        )
      ]
    )

    state["current_player_id"] = ai_player.id.to_s

    game = Game.create!(
      status: "started",
      mode: "ai",
      state: state
    )

    @players << human_player
    @nations.concat([ai_nation, human_nation])
    @games << game

    [game, ai_player, human_player]
  end

  def create_nation(code)
    Nation.create!(
      name: code.humanize,
      code: code
    )
  end
end
