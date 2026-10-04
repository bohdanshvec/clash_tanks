require "test_helper"

class DeckTest < ActiveSupport::TestCase
  test "belongs to player" do
    player = create_player
    nation = Nation.create!(name: "СССР", code: "ussr")
    headquarters_card = create_headquarters_card(nation)

    deck = Deck.create!(
      player: player,
      nation: nation,
      headquarters_card: headquarters_card,
      name: "Основная колода"
    )

    assert_equal player, deck.player
  end

  test "belongs to nation" do
    player = create_player
    nation = Nation.create!(name: "СССР", code: "ussr")
    headquarters_card = create_headquarters_card(nation)

    deck = Deck.create!(
      player: player,
      nation: nation,
      headquarters_card: headquarters_card,
      name: "Основная колода"
    )

    assert_equal nation, deck.nation
  end

  test "belongs to headquarters card" do
    player = create_player
    nation = Nation.create!(name: "СССР", code: "ussr")
    headquarters_card = create_headquarters_card(nation)

    deck = Deck.create!(
      player: player,
      nation: nation,
      headquarters_card: headquarters_card,
      name: "Основная колода"
    )

    assert_equal headquarters_card, deck.headquarters_card
  end

  test "has many deck cards" do
    player = create_player
    nation = Nation.create!(name: "СССР", code: "ussr")
    headquarters_card = create_headquarters_card(nation)

    deck = Deck.create!(
      player: player,
      nation: nation,
      headquarters_card: headquarters_card,
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
    player = create_player
    nation = Nation.create!(name: "СССР", code: "ussr")
    headquarters_card = create_headquarters_card(nation)

    deck = Deck.create!(
      player: player,
      nation: nation,
      headquarters_card: headquarters_card,
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
    player = create_player
    nation = Nation.create!(name: "СССР", code: "ussr")
    headquarters_card = create_headquarters_card(nation)

    deck = Deck.create!(
      player: player,
      nation: nation,
      headquarters_card: headquarters_card,
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

  test "requires headquarters card" do
    player = create_player
    nation = Nation.create!(name: "СССР", code: "ussr")

    deck = Deck.new(
      player: player,
      nation: nation,
      name: "Основная колода"
    )

    assert_not deck.valid?
    assert_includes deck.errors[:headquarters_card], "must exist"
  end

  test "requires headquarters card to be a headquarters" do
    player = create_player
    nation = Nation.create!(name: "СССР", code: "ussr")

    card = Card.create!(
      code: "test_not_headquarters",
      nation: nation,
      name: "Т-34",
      card_type: "technique",
      weight: 1,
      price: 2
    )

    deck = Deck.new(
      player: player,
      nation: nation,
      headquarters_card: card,
      name: "Основная колода"
    )

    assert_not deck.valid?
    assert_includes deck.errors[:headquarters_card], "must be a headquarters card"
  end

  test "requires headquarters card to belong to deck nation" do
    player = create_player
    germany = Nation.create!(name: "Германия", code: "germany")
    ussr = Nation.create!(name: "СССР", code: "ussr")
    headquarters_card = create_headquarters_card(germany)

    deck = Deck.new(
      player: player,
      nation: ussr,
      headquarters_card: headquarters_card,
      name: "Основная колода"
    )

    assert_not deck.valid?
    assert_includes deck.errors[:headquarters_card], "must belong to the same nation as the deck"
  end

  test "complete when headquarters and ten cards are present" do
    player = create_player
    nation = Nation.create!(name: "СССР", code: "ussr")
    headquarters_card = create_headquarters_card(nation)

    deck = Deck.create!(
      player: player,
      nation: nation,
      headquarters_card: headquarters_card,
      name: "Основная колода"
    )

    10.times do |index|
      card = Card.create!(
        code: "test_complete_#{index}",
        nation: nation,
        name: "Карта #{index}",
        card_type: "technique",
        weight: 1,
        price: 2
      )

      DeckCard.create!(
        deck: deck,
        card: card,
        quantity: 1
      )
    end

    assert deck.complete?
  end

  test "not complete without headquarters" do
    player = create_player
    nation = Nation.create!(name: "СССР", code: "ussr")

    deck = Deck.new(
      player: player,
      nation: nation,
      name: "Основная колода"
    )

    assert_not deck.complete?
  end

  test "not complete with fewer than ten cards" do
    player = create_player
    nation = Nation.create!(name: "СССР", code: "ussr")
    headquarters_card = create_headquarters_card(nation)

    deck = Deck.create!(
      player: player,
      nation: nation,
      headquarters_card: headquarters_card,
      name: "Основная колода"
    )

    9.times do |index|
      card = Card.create!(
        code: "test_incomplete_#{index}",
        nation: nation,
        name: "Карта #{index}",
        card_type: "technique",
        weight: 1,
        price: 2
      )

      DeckCard.create!(
        deck: deck,
        card: card,
        quantity: 1
      )
    end

    assert_not deck.complete?
  end

  test "calculates weight from deck cards only" do
    player = create_player
    nation = Nation.create!(name: "СССР", code: "ussr")
    headquarters_card = create_headquarters_card(nation, weight: 10)

    deck = Deck.create!(
      player: player,
      nation: nation,
      headquarters_card: headquarters_card,
      name: "Основная колода"
    )

    card_one = Card.create!(
      code: "test_weight_one",
      nation: nation,
      name: "Карта 1",
      card_type: "technique",
      weight: 2,
      price: 2
    )

    card_two = Card.create!(
      code: "test_weight_two",
      nation: nation,
      name: "Карта 2",
      card_type: "technique",
      weight: 3,
      price: 3
    )

    DeckCard.create!(deck: deck, card: card_one, quantity: 2)
    DeckCard.create!(deck: deck, card: card_two, quantity: 3)

    assert_equal 13, deck.weight
  end

  test "requires name" do
    player = create_player
    nation = Nation.create!(name: "СССР", code: "ussr")
    headquarters_card = create_headquarters_card(nation)

    deck = Deck.new(
      player: player,
      nation: nation,
      headquarters_card: headquarters_card
    )

    assert_not deck.valid?
    assert_includes deck.errors[:name], "can't be blank"
  end
  
  test "rejects more than ten cards" do
    player = create_player
    nation = Nation.create!(name: "СССР", code: "ussr")
    headquarters_card = create_headquarters_card(nation)

    deck = Deck.create!(
      player: player,
      nation: nation,
      headquarters_card: headquarters_card,
      name: "Основная колода"
    )

    11.times do |index|
      card = Card.create!(
        code: "test_limit_#{index}",
        nation: nation,
        name: "Карта #{index}",
        card_type: "technique",
        weight: 1,
        price: 2
      )

      DeckCard.create!(
        deck: deck,
        card: card,
        quantity: 1
      )
    end

    assert_not deck.valid?
    assert_includes deck.errors[:base], "cannot contain more than 10 cards"
  end

  private

  def create_headquarters_card(nation, weight: 1)
    Card.create!(
      code: "test_headquarters_#{SecureRandom.hex(4)}",
      nation: nation,
      name: "Тестовый штаб",
      card_type: "headquarters",
      weight: weight,
      price: nil
    )
  end
end
