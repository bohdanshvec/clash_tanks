require "test_helper"

class DeckCardTest < ActiveSupport::TestCase
  setup do
    @player = Player.create!
    @nation = Nation.create!(name: "СССР", code: "ussr")

    @deck = Deck.create!(
      player: @player,
      nation: @nation,
      name: "Основная колода"
    )

    @card = Card.create!(
      nation: @nation,
      name: "Т-34",
      card_type: "technique",
      weight: 1,
      price: 2
    )
  end

  test "belongs to deck" do
    deck_card = DeckCard.create!(
      deck: @deck,
      card: @card,
      quantity: 1
    )

    assert_equal @deck, deck_card.deck
  end

  test "belongs to card" do
    deck_card = DeckCard.create!(
      deck: @deck,
      card: @card,
      quantity: 1
    )

    assert_equal @card, deck_card.card
  end

  test "accepts quantity 1" do
    deck_card = DeckCard.new(
      deck: @deck,
      card: @card,
      quantity: 1
    )

    assert deck_card.valid?
  end

  test "accepts quantity 3" do
    deck_card = DeckCard.new(
      deck: @deck,
      card: @card,
      quantity: 3
    )

    assert deck_card.valid?
  end

  test "rejects quantity below 1" do
    deck_card = DeckCard.new(
      deck: @deck,
      card: @card,
      quantity: 0
    )

    assert_not deck_card.valid?
    assert deck_card.errors[:quantity].any?
  end

  test "rejects quantity above 3" do
    deck_card = DeckCard.new(
      deck: @deck,
      card: @card,
      quantity: 4
    )

    assert_not deck_card.valid?
    assert deck_card.errors[:quantity].any?
  end

  test "rejects duplicate card in the same deck" do
    DeckCard.create!(
      deck: @deck,
      card: @card,
      quantity: 1
    )

    duplicate = DeckCard.new(
      deck: @deck,
      card: @card,
      quantity: 1
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:card_id], "has already been taken"
  end

  test "rejects card from another nation" do
    other_nation = Nation.create!(
      name: "Германия",
      code: "germany"
    )

    other_card = Card.create!(
      nation: other_nation,
      name: "Panzer IV",
      card_type: "technique",
      weight: 1,
      price: 2
    )

    deck_card = DeckCard.new(
      deck: @deck,
      card: other_card,
      quantity: 1
    )

    assert_not deck_card.valid?
    assert_includes deck_card.errors[:card], "must belong to the same nation as the deck"
  end
end
