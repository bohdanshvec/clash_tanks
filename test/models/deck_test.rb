require "test_helper"

class DeckTest < ActiveSupport::TestCase
  test "belongs to player" do
    player = Player.create!
    nation = Nation.create!(name: "СССР", code: "ussr")

    deck = Deck.create!(
      player: player,
      nation: nation,
      name: "Основная колода"
    )

    assert_equal player, deck.player
  end

  test "belongs to nation" do
    player = Player.create!
    nation = Nation.create!(name: "СССР", code: "ussr")

    deck = Deck.create!(
      player: player,
      nation: nation,
      name: "Основная колода"
    )

    assert_equal nation, deck.nation
  end

  test "has many deck cards" do
    player = Player.create!
    nation = Nation.create!(name: "СССР", code: "ussr")

    deck = Deck.create!(
      player: player,
      nation: nation,
      name: "Основная колода"
    )

    card = Card.create!(
      code: "test_t34",
      nation: nation,
      name: "Т-34",
      card_type: "technique",
      weight: 1,
      price: 2
    )

    deck_card = DeckCard.create!(
      deck: deck,
      card: card,
      quantity: 2
    )

    assert_includes deck.deck_cards, deck_card
  end

  test "has many cards through deck cards" do
    player = Player.create!
    nation = Nation.create!(name: "СССР", code: "ussr")

    deck = Deck.create!(
      player: player,
      nation: nation,
      name: "Основная колода"
    )

    card = Card.create!(
      code: "test_t34_through_deck",
      nation: nation,
      name: "Т-34",
      card_type: "technique",
      weight: 1,
      price: 2
    )

    DeckCard.create!(
      deck: deck,
      card: card,
      quantity: 2
    )

    assert_includes deck.cards, card
  end

  test "counts cards using quantities" do
    player = Player.create!
    nation = Nation.create!(name: "СССР", code: "ussr")

    deck = Deck.create!(
      player: player,
      nation: nation,
      name: "Основная колода"
    )

    card_one = Card.create!(
      code: "test_t34_count",
      nation: nation,
      name: "Т-34",
      card_type: "technique",
      weight: 1,
      price: 2
    )

    card_two = Card.create!(
      code: "test_is2_count",
      nation: nation,
      name: "ИС-2",
      card_type: "technique",
      weight: 2,
      price: 3
    )

    DeckCard.create!(
      deck: deck,
      card: card_one,
      quantity: 3
    )

    DeckCard.create!(
      deck: deck,
      card: card_two,
      quantity: 2
    )

    assert_equal 5, deck.card_count
  end

  test "requires name" do
    player = Player.create!
    nation = Nation.create!(name: "СССР", code: "ussr")

    deck = Deck.new(
      player: player,
      nation: nation
    )

    assert_not deck.valid?
    assert_includes deck.errors[:name], "can't be blank"
  end
end
