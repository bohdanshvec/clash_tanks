# test/controllers/games_controller_ai_test.rb

require "test_helper"

class GamesControllerAiTest < ActionDispatch::IntegrationTest
  setup do
    @human = create_player(
      email: "human-ai-controller-#{SecureRandom.hex(6)}@example.com"
    )

    @ai = Player.find_by(ai: true)

    unless @ai
      @ai = create_player(
        email: "ai-controller-#{SecureRandom.hex(6)}@example.com"
      )

      @ai.update!(ai: true)
    end

    @human_deck = create_complete_deck(
      player: @human,
      name: "Human AI controller deck"
    )

    @ai_deck = create_complete_deck(
      player: @ai,
      name: "AI controller deck"
    )

    @game = Game.create!(
      status: "started",
      mode: "ai"
    )

    @game.game_players.create!(
      player: @human,
      nation: @human_deck.nation,
      deck: @human_deck,
      headquarters_card: @human_deck.headquarters_card
    )

    @game.game_players.create!(
      player: @ai,
      nation: @ai_deck.nation,
      deck: @ai_deck,
      headquarters_card: @ai_deck.headquarters_card
    )

    state = GameEngine::GameState.initial(
      current_player_id: @human.id,
      participants: [
        headquarters_participant(
          player_id: @human.id,
          nation_id: @human_deck.nation_id
        ),
        headquarters_participant(
          player_id: @ai.id,
          nation_id: @ai_deck.nation_id
        )
      ]
    )

    state["current_player_id"] = @human.id.to_s

    @game.update!(state: state)

    post login_path, params: {
      email: @human.email,
      password: "password"
    }
  end

  test "preserves human action and broadcasts updates when AI fails" do
    broadcasts = []

    failing_provider = lambda do |_visible_state|
      raise "Simulated external AI failure"
    end

    original_broadcast =
      Turbo::StreamsChannel.method(:broadcast_update_to)

    Turbo::StreamsChannel.define_singleton_method(
      :broadcast_update_to
    ) do |*args, **kwargs|
      broadcasts << [args, kwargs]
    end

    begin
      with_ai_decision_source(failing_provider) do
        post end_turn_path(@game)
      end
    ensure
      Turbo::StreamsChannel.define_singleton_method(
        :broadcast_update_to,
        original_broadcast
      )
    end

    assert_response :redirect

    @game.reload

    assert @game.started?
    assert_equal @ai.id.to_s, @game.state["current_player_id"].to_s
    assert_equal 2, @game.state["turn_number"]

    assert_equal 2, broadcasts.size

    expected_streams = [
      [@game, @human.id.to_s],
      [@game, @ai.id.to_s]
    ]

    assert_equal(
      expected_streams,
      broadcasts.map { |args, _kwargs| args.first }
    )

    broadcasts.each do |args, kwargs|
      viewer_id = args.first.last.to_s
      locals = kwargs.fetch(:locals)
      visible_state = locals.fetch(:visible_state)

      assert_equal(
        viewer_id,
        locals.fetch(:current_player_id).to_s
      )

      assert_equal(
        @ai.id.to_s,
        visible_state.fetch("current_player_id").to_s
      )

      assert_equal(
        2,
        visible_state.fetch("turn_number")
      )

      assert_equal "games/game", kwargs.fetch(:partial)
      assert_equal "game-content", kwargs.fetch(:target)

      opponent_id =
        viewer_id == @human.id.to_s ? @ai.id.to_s : @human.id.to_s

      refute(
        visible_state.fetch("players").fetch(opponent_id).key?("hand"),
        "Игрок не должен видеть закрытую руку противника"
      )
    end
  end

  test "retries AI turn when human opens game after provider failure" do
    state = @game.state.deep_dup
    state["current_player_id"] = @ai.id.to_s
    @game.update!(state: state)

    calls = 0

    decision_source = lambda do |_visible_state|
      calls += 1

      if calls == 1
        raise "Temporary external AI failure"
      end

      {
        "type" => "end_turn",
        "payload" => {}
      }
    end

    with_ai_decision_source(decision_source) do
      get game_path(@game)

      assert_response :success

      assert_equal(
        @ai.id.to_s,
        @game.reload.state["current_player_id"].to_s
      )

      get game_path(@game)

      assert_response :success
    end

    assert_equal 2, calls

    @game.reload

    assert @game.started?

    assert_equal(
      @human.id.to_s,
      @game.state["current_player_id"].to_s
    )
  end
  
  test "broadcasts each AI action separately when human opens game" do
    broadcasts = []
    calls = 0

    decision_source = lambda do |_visible_state|
      calls += 1

      if calls == 1
        {
          "type" => "attack",
          "payload" => {
            "attacker" => [0, 4],
            "target" => [2, 0]
          }
        }
      else
        {
          "type" => "end_turn",
          "payload" => {}
        }
      end
    end

    # Перед открытием страницы наступает ход ИИ.
    state = @game.state.deep_dup
    state["current_player_id"] = @ai.id.to_s
    @game.update!(state: state)

    original_broadcast =
      Turbo::StreamsChannel.method(:broadcast_update_to)

    Turbo::StreamsChannel.define_singleton_method(
      :broadcast_update_to
    ) do |*args, **kwargs|
      broadcasts << [args, kwargs]
    end

    begin
      with_ai_decision_source(decision_source) do
        get game_path(@game)
      end
    ensure
      Turbo::StreamsChannel.define_singleton_method(
        :broadcast_update_to,
        original_broadcast
      )
    end

    assert_response :success

    # ИИ выполнил атаку, затем завершил ход.
    assert_equal 2, calls

    @game.reload

    assert @game.started?

    assert_equal(
      @human.id.to_s,
      @game.state["current_player_id"].to_s
    )

    # Каждое из двух действий отправляется обоим участникам.
    assert_equal 4, broadcasts.size

    expected_streams = [
      [@game, @human.id.to_s],
      [@game, @ai.id.to_s],
      [@game, @human.id.to_s],
      [@game, @ai.id.to_s]
    ]

    assert_equal(
      expected_streams,
      broadcasts.map { |args, _kwargs| args.first }
    )

    broadcasts.each_slice(2).with_index do |action_broadcasts, index|
      action_broadcasts.each do |args, kwargs|
        viewer_id = args.first.last.to_s
        locals = kwargs.fetch(:locals)
        visible_state = locals.fetch(:visible_state)
        events = locals.fetch(:events)

        assert_equal(
          viewer_id,
          locals.fetch(:current_player_id).to_s
        )

        assert_equal(
          index.zero? ? @ai.id.to_s : @human.id.to_s,
          visible_state.fetch("current_player_id").to_s
        )

        assert_equal(
          index.zero? ? 1 : 2,
          visible_state.fetch("turn_number")
        )

        if index.zero?
          assert(
            events.any? do |event|
              event[:type] == "headquarters_attacked"
            end,
            "Первое обновление должно содержать событие атаки штаба"
          )
        else
          assert(
            events.any? { |event| event[:type] == "turn_ended" },
            "Второе обновление должно содержать событие завершения хода"
          )
        end

        assert_equal "games/game", kwargs.fetch(:partial)
        assert_equal "game-content", kwargs.fetch(:target)

        opponent_id =
          viewer_id == @human.id.to_s ? @ai.id.to_s : @human.id.to_s

        refute(
          visible_state.fetch("players").fetch(opponent_id).key?("hand"),
          "Игрок не должен видеть закрытую руку противника"
        )
      end
    end
  end

  private

  # Временно подменяем источник решений ИИ.
  # После выполнения блока исходный метод new восстанавливается.
  def with_ai_decision_source(decision_source)
    original_method = DecisionProviders::AI.method(:new)

    DecisionProviders::AI.define_singleton_method(:new) do |**options|
      original_method.call(
        **options.merge(decision_source: decision_source)
      )
    end

    begin
      yield
    ensure
      DecisionProviders::AI.define_singleton_method(
        :new,
        original_method
      )
    end
  end
end
