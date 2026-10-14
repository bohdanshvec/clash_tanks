require "test_helper"

class AiPlayers::DecksSetupTest < ActiveSupport::TestCase
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

  test "creates three complete AI decks with expected weights" do
    prepare_cards

    decks = AiPlayers::DecksSetup.call

    assert_equal 3, decks.size
    assert_equal [13, 22, 28], decks.map(&:weight).sort

    decks.each do |deck|
      assert deck.persisted?
      assert deck.complete?
      assert_equal 10, deck.card_count
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

  private

  def prepare_cards
    AiPlayers::DecksSetup::DECKS.each do |definition|
      nation = Nation.find_or_create_by!(code: definition[:nation_code]) do |record|
        record.name = definition[:nation_code].upcase
      end

      create_card(
        code: definition[:headquarters_code],
        nation: nation,
        name: definition[:name],
        card_type: "headquarters",
        weight: 1,
        price: nil
      )

      definition[:card_codes].each_key do |code|
        create_card(
          code: code,
          nation: nation,
          name: code,
          card_type: "technique",
          weight: CARD_WEIGHTS.fetch(code),
          price: 1
        )
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
end
