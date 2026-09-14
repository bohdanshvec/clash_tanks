require "test_helper"

class PlatoonTest < ActiveSupport::TestCase
  setup do
    @nation = Nation.create!(
      name: "Test Nation",
      code: "test"
    )

    @card = Card.create!(
      nation: @nation,
      name: "Test Platoon",
      card_type: "platoon",
      weight: 1,
      price: 2
    )
  end

  test "is valid with valid attributes" do
    platoon = Platoon.new(
      card: @card,
      firepower: 5,
      hp: 10,
      armor: 3,
      fuel: 2
    )

    assert platoon.valid?
  end

  test "requires card" do
    platoon = Platoon.new(
      firepower: 5,
      hp: 10,
      armor: 3,
      fuel: 2
    )

    assert_not platoon.valid?
    assert_includes platoon.errors[:card], "must exist"
  end

  test "requires positive firepower" do
    platoon = valid_platoon
    platoon.firepower = 0

    assert_not platoon.valid?
  end

  test "requires positive hp" do
    platoon = valid_platoon
    platoon.hp = 0

    assert_not platoon.valid?
  end

  test "allows zero armor" do
    platoon = valid_platoon
    platoon.armor = 0

    assert platoon.valid?
  end

  test "allows zero fuel" do
    platoon = valid_platoon
    platoon.fuel = 0

    assert platoon.valid?
  end

  test "does not allow negative armor" do
    platoon = valid_platoon
    platoon.armor = -1

    assert_not platoon.valid?
  end

  test "does not allow negative fuel" do
    platoon = valid_platoon
    platoon.fuel = -1

    assert_not platoon.valid?
  end

  test "allows only one platoon per card" do
    Platoon.create!(
      card: @card,
      firepower: 5,
      hp: 10,
      armor: 3,
      fuel: 2
    )

    second_platoon = Platoon.new(
      card: @card,
      firepower: 6,
      hp: 12,
      armor: 4,
      fuel: 3
    )

    assert_not second_platoon.valid?
  end

  private

  def valid_platoon
    Platoon.new(
      card: @card,
      firepower: 5,
      hp: 10,
      armor: 3,
      fuel: 2
    )
  end
end
