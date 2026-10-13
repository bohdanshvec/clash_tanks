# test/services/games/run_ai_turns_test.rb

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
    provider_started = Queue.new
    release_provider = Queue.new
    first_result = Queue.new

    decision_source = lambda do |_visible_state|
      provider_started << true
      release_provider.pop

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
      # Ждём, пока первый запуск получит блокировку
      # и начнёт принимать решение ИИ.
      Timeout.timeout(10) do
        provider_started.pop
      end

      # Второй запуск для той же игры не должен
      # запускать провайдера параллельно.
      second_provider_called = false

      second_result = Games::RunAiTurns.call(
        game: @game,
        decision_source: lambda do |_visible_state|
          second_provider_called = true

          {
            "type" => "end_turn",
            "payload" => {}
          }
        end
      )

      assert second_result.success?, second_result.error
      assert_equal 0, second_result.actions_count
      assert_not second_provider_called
    ensure
      # Не оставляем поток заблокированным даже при ошибке теста.
      release_provider << true
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

    provider_started = Queue.new
    release_provider = Queue.new
    first_result = Queue.new

    decision_source = lambda do |_visible_state|
      provider_started << true
      release_provider.pop

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
        provider_started.pop
      end

      # Первая игра всё ещё заблокирована внутри провайдера.
      # Вторая игра должна обработаться независимо.
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
      release_provider << true
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

  test "releases the advisory lock after the AI provider raises an error" do
    failed_result = Games::RunAiTurns.call(
      game: @game,
      decision_source: lambda do |_visible_state|
        raise "Simulated AI provider failure"
      end
    )

    assert_not failed_result.success?
    assert_equal 0, failed_result.actions_count

    # После ошибки первый запуск обязан освободить блокировку.
    # Повторный вызов должен иметь возможность выполнить ход.
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

    # Возвращаем ход ИИ, чтобы повторный запуск мог выполнить действие.
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
  
  test "preserves successful AI action events when next decision fails" do
    calls = 0

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
        raise "Simulated AI failure after successful action"
      end
    end

    initial_state = @game.reload.state.deep_dup
    human_hq_initial_hp = initial_state.dig(
      "field", 0, 4, "hp"
    )

    result = Games::RunAiTurns.call(
      game: @game,
      decision_source: decision_source
    )

    assert_not result.success?
    assert_equal 1, result.actions_count
    assert_equal 2, calls

    assert_equal 1, result.events.size

    attack_event = result.events.first

    assert_equal "headquarters_attacked", attack_event[:type]
    assert_equal [2, 0], attack_event.dig(:attacker, :position)
    assert_equal [0, 4], attack_event.dig(:target, :position)

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
    provider_called = false

    result = Games::RunAiTurns.call(
      game: @game,
      max_actions: 0,
      decision_source: lambda do |_visible_state|
        provider_called = true

        {
          "type" => "end_turn",
          "payload" => {}
        }
      end
    )

    assert_not result.success?
    assert_equal 0, result.actions_count
    assert_not provider_called

    @game.reload

    assert @game.started?

    assert_equal(
      @ai_player.id.to_s,
      @game.state["current_player_id"].to_s
    )
  end

  test "releases the advisory lock after an invalid AI action" do
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

    # После недопустимого действия блокировка должна освободиться.
    # Повторный запуск должен успешно выполнить ход.
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
  
  test "retries an AI decision when the game state becomes stale" do
    calls = 0

    result = Games::RunAiTurns.call(
      game: @game,
      decision_source: lambda do |_visible_state|
        calls += 1

        if calls == 1
          # Имитируем изменение состояния другим запросом
          # после формирования контекста ИИ.
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

        # Каждое решение устаревает до применения действия.
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

  test "stops when the game finishes during an AI decision" do
    calls = 0

    result = Games::RunAiTurns.call(
      game: @game,
      decision_source: lambda do |_visible_state|
        calls += 1

        # Имитируем завершение игры другим запросом,
        # пока провайдер формирует решение.
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

  test "stops when the turn passes to a human during an AI decision" do
    calls = 0

    result = Games::RunAiTurns.call(
      game: @game,
      decision_source: lambda do |_visible_state|
        calls += 1

        # Имитируем передачу хода человеку другим запросом.
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
  
  private

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
