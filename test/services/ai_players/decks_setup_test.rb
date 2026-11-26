
require "test_helper"

class AiPlayers::DecksSetupTest < ActiveSupport::TestCase
  test "creates three complete AI decks with expected weights" do
    prepare_cards

    decks = AiPlayers::DecksSetup.call

    assert_equal 3, decks.size
    assert_equal [67, 73, 78], decks.map(&:weight).sort

    decks.each do |deck|
      assert deck.persisted?
      assert deck.complete?
      assert_equal 15, deck.card_count
      assert deck.player.ai?
      assert_equal deck.nation_id, deck.headquarters_card.nation_id
      assert_equal "headquarters", deck.headquarters_card.card_type

      deck.deck_cards.each do |deck_card|
        assert_includes 1..3, deck_card.quantity
        refute_equal "headquarters", deck_card.card.card_type
        assert_equal deck.nation_id, deck_card.card.nation_id
      end
    end
  end

  test "repeated calls do not create duplicate AI decks or cards" do
    prepare_cards

    first_decks = AiPlayers::DecksSetup.call
    first_deck_ids = first_decks.map(&:id).sort
    first_deck_card_count = DeckCard.joins(:deck)
                                    .where(decks: { player_id: first_decks.first.player_id })
                                    .count

    assert_no_difference -> { Deck.where(player_id: first_decks.first.player_id).count } do
      assert_no_difference -> { DeckCard.joins(:deck).where(decks: { player_id: first_decks.first.player_id }).count } do
        second_decks = AiPlayers::DecksSetup.call

        assert_equal first_deck_ids, second_decks.map(&:id).sort
      end
    end

    assert_equal first_deck_card_count,
                 DeckCard.joins(:deck)
                         .where(decks: { player_id: first_decks.first.player_id })
                         .count
  end

  test "updates changed AI deck composition without changing its ID" do
    prepare_cards

    original_deck = ai_deck
    original_id = original_deck.id
    original_cards = deck_composition(original_deck)

    with_changed_usa_definition do
      updated_decks = AiPlayers::DecksSetup.call
      updated_deck = updated_decks.find { |deck| deck.id == original_id }

      assert updated_deck
      assert_equal original_id, updated_deck.id
      assert_equal 15, updated_deck.card_count
      assert updated_deck.complete?
      refute_equal original_cards, deck_composition(updated_deck)

      assert_equal(
        {
          "usa_m4_sherman" => 2,
          "usa_m4a3e8" => 3,
          "usa_m4a3e2" => 3,
          "usa_m10_wolverine" => 3,
          "usa_m26_pershing" => 3,
          "usa_m8_greyhound" => 1
        },
        deck_composition(updated_deck)
      )
    end
  end

  test "cancels waiting game before changing AI deck composition" do
    prepare_cards

    deck = ai_deck
    game = Game.create!(mode: "pvp", status: "waiting")

    game_player = game.game_players.create!(
      player: deck.player,
      nation: deck.nation,
      deck: deck,
      headquarters_card: deck.headquarters_card
    )

    with_changed_usa_definition do
      AiPlayers::DecksSetup.call

      assert_not Game.exists?(game.id)
      assert_not GamePlayer.exists?(game_player.id)

      deck.reload
      assert_equal 15, deck.card_count
      assert_equal deck.id, Deck.find(deck.id).id
      assert_equal 2, deck.deck_cards.find_by!(
        card: Card.find_by!(code: "usa_m4_sherman")
      ).quantity
    end
  end

  test "surrenders AI in started game before changing its deck" do
    prepare_cards

    deck = ai_deck
    opponent = create_player(email: "sync-opponent@example.com")
    opponent_deck = create_complete_deck(player: opponent)

    game = create_started_game(
      ai_deck: deck,
      opponent_deck: opponent_deck
    )

    ai_game_player = game.game_players.find_by!(player: deck.player)
    opponent_game_player = game.game_players.find_by!(player: opponent)

    ai_statistics_before = player_statistics(deck.player)
    opponent_statistics_before = player_statistics(opponent)

    with_changed_usa_definition do
      AiPlayers::DecksSetup.call

      game.reload
      assert game.finished?

      result = game.state.fetch("result")
      assert_equal "surrender", result.fetch("reason")
      assert_equal opponent.id, result.fetch("winner_id").to_i
      assert_equal deck.player.id, result.fetch("loser_id").to_i

      assert_nil ai_game_player.reload.deck_id
      assert_equal opponent_deck.id, opponent_game_player.reload.deck_id

      assert_equal ai_statistics_before, player_statistics(deck.player)
      assert_equal opponent_statistics_before, player_statistics(opponent)

      assert_equal deck.id, Deck.find(deck.id).id
      assert_equal 15, deck.reload.card_count
    end
  end

  test "preserves finished game history when changing AI deck" do
    prepare_cards

    deck = ai_deck
    opponent = create_player(email: "finished-sync-opponent@example.com")
    opponent_deck = create_complete_deck(player: opponent)

    game = create_started_game(
      ai_deck: deck,
      opponent_deck: opponent_deck
    )

    surrender_game!(game: game, player: opponent)

    game.reload
    original_result = game.state.fetch("result").deep_dup
    ai_statistics_before = player_statistics(deck.player)
    opponent_statistics_before = player_statistics(opponent)

    ai_game_player = game.game_players.find_by!(player: deck.player)
    opponent_game_player = game.game_players.find_by!(player: opponent)

    with_changed_usa_definition do
      AiPlayers::DecksSetup.call

      game.reload

      assert game.finished?
      assert_equal original_result, game.state.fetch("result")

      assert_nil ai_game_player.reload.deck_id
      assert_equal opponent_deck.id, opponent_game_player.reload.deck_id

      assert_equal ai_statistics_before, player_statistics(deck.player)
      assert_equal opponent_statistics_before, player_statistics(opponent)

      assert_equal deck.id, Deck.find(deck.id).id
      assert_equal 15, deck.reload.card_count
    end
  end

  test "removes AI decks that are no longer present in definitions" do
    prepare_cards

    decks = AiPlayers::DecksSetup.call
    removed_deck = decks.first
    retained_ids = decks.drop(1).map(&:id)

    remaining_definitions = AiPlayers::DecksSetup::DECKS.drop(1)

    with_deck_definitions(remaining_definitions) do
      result = AiPlayers::DecksSetup.call

      assert_equal retained_ids.sort, result.map(&:id).sort
      assert_not Deck.exists?(removed_deck.id)
      assert_equal 2, Deck.where(player: removed_deck.player).count
    end
  end

  private

  def prepare_cards
    Rails.application.load_seed
  end

  def ai_deck
    player = AiPlayers::Setup.call

    Deck.find_by!(
      player: player,
      name: "АІ — США: важка техніка"
    )
  end

  def deck_composition(deck)
    deck.deck_cards.includes(:card).each_with_object({}) do |deck_card, result|
      result[deck_card.card.code] = deck_card.quantity
    end
  end

  def changed_usa_definitions
    AiPlayers::DecksSetup::DECKS.map(&:deep_dup).tap do |definitions|
      definitions.first[:card_codes] = {
        "usa_m4_sherman" => 2,
        "usa_m4a3e8" => 3,
        "usa_m4a3e2" => 3,
        "usa_m10_wolverine" => 3,
        "usa_m26_pershing" => 3,
        "usa_m8_greyhound" => 1
      }
    end
  end

  def with_changed_usa_definition(&block)
    with_deck_definitions(changed_usa_definitions, &block)
  end

  def with_deck_definitions(definitions)
    original = AiPlayers::DecksSetup.send(:remove_const, :DECKS)
    AiPlayers::DecksSetup.const_set(:DECKS, definitions)

    yield
  ensure
    AiPlayers::DecksSetup.send(:remove_const, :DECKS)
    AiPlayers::DecksSetup.const_set(:DECKS, original)
  end

  def create_started_game(ai_deck:, opponent_deck:)
    game = Game.create!(
      mode: "ai",
      status: "waiting"
    )

    [
      [ai_deck.player, ai_deck],
      [opponent_deck.player, opponent_deck]
    ].each do |player, deck|
      game.game_players.create!(
        player: player,
        nation: deck.nation,
        deck: deck,
        headquarters_card: deck.headquarters_card
      )
    end

    GameEngine::StartGame.call(game)

    game.reload
  end

  def surrender_game!(game:, player:)
    action = DecisionProviders::Human.new(
      player_id: player.id.to_s,
      type: "surrender"
    ).call

    result = GameActionRunner.call(
      game: game,
      action: action
    )

    assert_predicate result, :success?, result.error

    game.reload
  end

  def player_statistics(player)
    player.reload.attributes.slice(
      "battles_count",
      "wins_count",
      "losses_count"
    )
  end
end
