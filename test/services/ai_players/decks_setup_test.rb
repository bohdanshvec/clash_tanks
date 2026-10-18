require "test_helper"

class AiPlayers::DecksSetupTest < ActiveSupport::TestCase

  test "creates three complete AI decks with expected weights" do
    prepare_cards

    decks = AiPlayers::DecksSetup.call

    assert_equal 3, decks.size
    assert_equal [40, 50, 58], decks.map(&:weight).sort

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
		Rails.application.load_seed
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
