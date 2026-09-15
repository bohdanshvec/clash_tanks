require "test_helper"

class HeadquartersTest < ActiveSupport::TestCase
  setup do
    @nation = Nation.create!(
      name: "Test Nation",
      code: "test"
    )

    @card = Card.create!(
      nation: @nation,
      name: "Test HQ",
      card_type: "headquarters",
      weight: 1,
      price: nil
    )
  end

  test "is valid with valid attributes" do
    headquarters = Headquarters.new(
      card: @card,
      hp: 20,
      firepower: 3,
      fuel: 5
    )

    assert_predicate headquarters, :valid?
  end

  test "belongs to card" do
    headquarters = Headquarters.create!(
      card: @card,
      hp: 20,
      firepower: 3,
      fuel: 5
    )

    assert_equal @card, headquarters.card
  end

  test "card can have headquarters" do
    headquarters = Headquarters.create!(
      card: @card,
      hp: 20,
      firepower: 3,
      fuel: 5
    )

    assert_equal headquarters, @card.reload.headquarters
  end

  test "hp must be greater than zero" do
    headquarters = Headquarters.new(
      card: @card,
      hp: 0,
      firepower: 3,
      fuel: 5
    )

    assert_not headquarters.valid?
  end

  test "firepower cannot be negative" do
    headquarters = Headquarters.new(
      card: @card,
      hp: 20,
      firepower: -1,
      fuel: 5
    )

    assert_not headquarters.valid?
  end

  test "fuel cannot be negative" do
    headquarters = Headquarters.new(
      card: @card,
      hp: 20,
      firepower: 3,
      fuel: -1
    )

    assert_not headquarters.valid?
  end
end
