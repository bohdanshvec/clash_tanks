require "test_helper"

class NationTest < ActiveSupport::TestCase
  test "has many cards" do
    nation = Nation.create!(name: "СССР", code: "ussr")

    card = Card.create!(
      code: "test_t34",
      nation: nation,
      name: "Т-34",
      card_type: "technique",
      weight: 1,
      price: 2
    )

    assert_includes nation.cards, card
  end

  test "has many decks" do
    player = Player.create!

    nation = Nation.create!(
      name: "СССР",
      code: "ussr"
    )

    deck = Deck.create!(
      player: player,
      nation: nation,
      name: "Основная колода"
    )

    assert_includes nation.decks, deck
  end

  test "requires name" do
    nation = Nation.new(code: "ussr")

    assert_not nation.valid?
    assert_includes nation.errors[:name], "can't be blank"
  end

  test "requires code" do
    nation = Nation.new(name: "СССР")

    assert_not nation.valid?
    assert_includes nation.errors[:code], "can't be blank"
  end

  test "requires unique code" do
    Nation.create!(name: "СССР", code: "ussr")

    nation = Nation.new(
      name: "Другая нация",
      code: "ussr"
    )

    assert_not nation.valid?
    assert_includes nation.errors[:code], "has already been taken"
  end
end
