require "test_helper"

class Matchmaking::CreateAiGameTest < ActiveSupport::TestCase
  CARD_WEIGHTS = {
    "usa_m3_stuart" => 1,
    "usa_m8_greyhound" => 1,
    "usa_m24_chaffee" => 2,
    "usa_m4_sherman" => 2,
    "usa_lend_liz" => 1,
    "usa_ognevoj_nalyot" => 1,

    "ussr_t_34" => 2,
    "ussr_t_34_85" => 3,
    "ussr_is_2" => 3,
    "ussr_t_70" => 1,
    "ussr_zalp_katyushi" => 2,
    "ussr_popolnenie" => 2,
    "ussr_strelkovyj_vzvod" => 2,

    "germany_tiger_i" => 4,
    "germany_jagdpanther" => 3,
    "germany_pz_iv_h" => 2,
    "germany_hummel" => 2,
    "germany_tocnyj_vystrel" => 3,
    "germany_radioperekhvat" => 2,
    "germany_grenaderskij_vzvod" => 2
  }.freeze

  setup do
    prepare_cards

    @ai_decks = AiPlayers::DecksSetup.call

    @player = Player.create!(
      name: "Human",
      email: "human-ai-game@example.com",
      password: "password123"
    )

    @player_deck = create_player_deck
  end

  test "creates started AI game with human and AI players" do
    game = nil

    assert_difference "Game.count", 1 do
      assert_difference "GamePlayer.count", 2 do
        game = Matchmaking::CreateAiGame.call(
          player: @player,
          deck: @player_deck
        )
      end
    end

    assert game.persisted?
    assert game.ai?
    assert game.started?
    assert_not_nil game.state

    assert_equal 2, game.game_players.count

    human_participant = game.game_players.find_by!(
      player: @player
    )

    ai_participant = game.game_players.joins(:player).find_by!(
      players: { ai: true }
    )

    assert_equal @player_deck.id, human_participant.deck_id
    assert_equal @player_deck.nation_id, human_participant.nation_id
    assert_equal @player_deck.headquarters_card_id,
                 human_participant.headquarters_card_id

    assert_equal @ai_decks.first.id, ai_participant.deck_id

    assert_equal(
      [@player.id.to_s, ai_participant.player_id.to_s].sort,
      game.state.fetch("players").keys.sort
    )

    assert_includes(
      [@player.id.to_s, ai_participant.player_id.to_s],
      game.state.fetch("current_player_id").to_s
    )
  end

  test "rejects incomplete human deck without creating game" do
    @player_deck.deck_cards.first.destroy!

    assert_no_difference "Game.count" do
      assert_raises(ArgumentError) do
        Matchmaking::CreateAiGame.call(
          player: @player,
          deck: @player_deck
        )
      end
    end
  end

  test "rejects deck belonging to another player" do
    another_player = Player.create!(
      name: "Another Human",
      email: "another-human-ai-game@example.com",
      password: "password123"
    )

    assert_no_difference "Game.count" do
      assert_raises(ArgumentError) do
        Matchmaking::CreateAiGame.call(
          player: another_player,
          deck: @player_deck
        )
      end
    end
  end

  test "rejects AI player as game creator" do
    ai_player = @ai_decks.first.player

    assert_no_difference "Game.count" do
      assert_raises(ArgumentError) do
        Matchmaking::CreateAiGame.call(
          player: ai_player,
          deck: @ai_decks.first
        )
      end
    end
  end
  
  test "automatically executes AI turn and stops when human turn begins" do
    game = Matchmaking::CreateAiGame.call(
      player: @player,
      deck: @player_deck
    )

    ai_participant = game.game_players.joins(:player).find_by!(
      players: { ai: true }
    )

    state = game.state.deep_dup
    state["current_player_id"] = ai_participant.player_id.to_s

    game.update!(state: state)

    calls = 0

    decision_source = lambda do |visible_state|
      calls += 1

      assert_equal(
        ai_participant.player_id.to_s,
        visible_state["current_player_id"].to_s
      )

      {
        "type" => "end_turn",
        "payload" => {}
      }
    end

    result = Games::RunAiTurns.call(
      game: game,
      decision_source: decision_source
    )

    assert result.success?, result.error
    assert_equal 1, result.actions_count
    assert_equal 1, calls

    game.reload

    assert game.started?
    assert_equal @player.id.to_s, game.state["current_player_id"].to_s
  end

  test "does not call AI provider when it is human turn" do
    game = Matchmaking::CreateAiGame.call(
      player: @player,
      deck: @player_deck
    )

    state = game.state.deep_dup
    state["current_player_id"] = @player.id.to_s

    game.update!(state: state)

    provider_called = false

    result = Games::RunAiTurns.call(
      game: game,
      decision_source: lambda do |_visible_state|
        provider_called = true

        {
          "type" => "end_turn",
          "payload" => {}
        }
      end
    )

    assert result.success?, result.error
    assert_equal 0, result.actions_count
    assert_not provider_called
  end

  test "does not execute AI actions after game has finished" do
    game = Matchmaking::CreateAiGame.call(
      player: @player,
      deck: @player_deck
    )

    game.update!(status: :finished)

    provider_called = false

    result = Games::RunAiTurns.call(
      game: game,
      decision_source: lambda do |_visible_state|
        provider_called = true

        {
          "type" => "end_turn",
          "payload" => {}
        }
      end
    )

    assert result.success?, result.error
    assert_equal 0, result.actions_count
    assert_not provider_called
  end

  test "returns failure when AI provider raises an error" do
    game = Matchmaking::CreateAiGame.call(
      player: @player,
      deck: @player_deck
    )

    ai_participant = game.game_players.joins(:player).find_by!(
      players: { ai: true }
    )

    state = game.state.deep_dup
    state["current_player_id"] = ai_participant.player_id.to_s

    game.update!(state: state)

    result = Games::RunAiTurns.call(
      game: game,
      decision_source: lambda do |_visible_state|
        raise "Test AI provider failure"
      end
    )

    assert_not result.success?
    assert_equal 0, result.actions_count
    assert_includes result.error, "Не удалось выполнить ход ИИ"

    game.reload

    assert_equal(
      ai_participant.player_id.to_s,
      game.state["current_player_id"].to_s
    )
  end
  
  test "retries AI decision when game state changes during decision making" do
    game = Matchmaking::CreateAiGame.call(
      player: @player,
      deck: @player_deck
    )

    ai_participant = game.game_players.joins(:player).find_by!(
      players: { ai: true }
    )

    state = game.state.deep_dup
    state["current_player_id"] = ai_participant.player_id.to_s

    game.update!(state: state)

    calls = 0

    decision_source = lambda do |_visible_state|
      calls += 1

      if calls == 1
        # Имитируем изменение состояния другим запросом
        # после создания контекста, но до применения действия.
        changed_state = game.reload.state.deep_dup
        changed_state["turn_number"] += 1

        game.update!(state: changed_state)
      end

      {
        "type" => "end_turn",
        "payload" => {}
      }
    end

    result = Games::RunAiTurns.call(
      game: game,
      decision_source: decision_source
    )

    assert result.success?, result.error
    assert_equal 1, result.actions_count
    assert_equal 2, calls

    game.reload

    assert game.started?
    assert_equal @player.id.to_s, game.state["current_player_id"].to_s
  end

  test "stops retrying AI decisions after the retry limit" do
    game = Matchmaking::CreateAiGame.call(
      player: @player,
      deck: @player_deck
    )

    ai_participant = game.game_players.joins(:player).find_by!(
      players: { ai: true }
    )

    state = game.state.deep_dup
    state["current_player_id"] = ai_participant.player_id.to_s

    game.update!(state: state)

    calls = 0

    decision_source = lambda do |_visible_state|
      calls += 1

      # Каждое решение становится устаревшим до применения.
      changed_state = game.reload.state.deep_dup
      changed_state["turn_number"] += 1

      game.update!(state: changed_state)

      {
        "type" => "end_turn",
        "payload" => {}
      }
    end

    result = Games::RunAiTurns.call(
      game: game,
      decision_source: decision_source
    )

    refute result.success?

    assert_includes(
      result.error,
      "Не удалось получить актуальное решение ИИ"
    )

    assert_equal 0, result.actions_count
    assert_equal(
      Games::RunAiTurns::MAX_STALE_STATE_RETRIES + 1,
      calls
    )

    game.reload

    # Ни одно устаревшее действие не должно завершить ход ИИ.
    assert_equal(
      ai_participant.player_id.to_s,
      game.state["current_player_id"].to_s
    )
  end
  
  test "retries AI turn after a previous provider failure" do
    game = Matchmaking::CreateAiGame.call(
      player: @player,
      deck: @player_deck
    )

    ai_participant = game.game_players.joins(:player).find_by!(
      players: { ai: true }
    )

    state = game.state.deep_dup
    state["current_player_id"] = ai_participant.player_id.to_s

    game.update!(state: state)

    first_result = Games::RunAiTurns.call(
      game: game,
      decision_source: lambda do |_visible_state|
        raise "Temporary AI provider failure"
      end
    )

    assert_not first_result.success?
    assert_equal 0, first_result.actions_count

    game.reload

    assert_equal(
      ai_participant.player_id.to_s,
      game.state["current_player_id"].to_s
    )

    second_result = Games::RunAiTurns.call(
      game: game,
      decision_source: ->(_visible_state) do
        {
          "type" => "end_turn",
          "payload" => {}
        }
      end
    )

    assert second_result.success?, second_result.error
    assert_equal 1, second_result.actions_count

    game.reload

    assert_equal(
      @player.id.to_s,
      game.state["current_player_id"].to_s
    )
  end

  private

  def prepare_cards
    AiPlayers::DecksSetup::DECKS.each do |definition|
      nation = Nation.find_or_create_by!(
        code: definition[:nation_code]
      ) do |record|
        record.name = definition[:nation_code].upcase
      end

      headquarters_card = create_card(
        code: definition[:headquarters_code],
        nation: nation,
        name: definition[:name],
        card_type: "headquarters",
        weight: 1,
        price: nil
      )

      Headquarters.find_or_create_by!(
        card: headquarters_card
      ) do |headquarters|
        headquarters.hp = 20
        headquarters.firepower = 3
        headquarters.fuel = 5
      end

      definition[:card_codes].each_key do |code|
        card = create_card(
          code: code,
          nation: nation,
          name: code,
          card_type: "technique",
          weight: CARD_WEIGHTS.fetch(code),
          price: 1
        )

        Technique.find_or_create_by!(
          card: card
        ) do |technique|
          technique.technique_type = "light_tank"
          technique.attack_range = 1
          technique.movement_count = 1
          technique.movement_type = "orthogonal"
          technique.firepower = 1
          technique.hp = 1
          technique.fuel = 0
        end
      end
    end
  end

  def create_card(code:, nation:, name:, card_type:, weight:, price:)
    Card.find_or_create_by!(code: code) do |card|
      card.nation = nation
      card.name = name
      card.card_type = card_type
      card.weight = weight
      card.price = price
    end
  end

  def create_player_deck
    ai_deck = @ai_decks.first

    deck = Deck.create!(
      player: @player,
      nation: ai_deck.nation,
      headquarters_card: ai_deck.headquarters_card,
      name: "Human AI test deck"
    )

    ai_deck.deck_cards.each do |deck_card|
      deck.deck_cards.create!(
        card: deck_card.card,
        quantity: deck_card.quantity
      )
    end

    deck
  end
end
