require "test_helper"

class CardTest < ActiveSupport::TestCase
  test "belongs to nation" do
    nation = Nation.create!(name: "СССР", code: "ussr")

    card = Card.create!(
      code: "test_card",
      nation: nation,
      name: "Т-34",
      card_type: "technique",
      weight: 1,
      price: 2
    )

    assert_equal nation, card.nation
  end

  test "has one technique" do
    nation = Nation.create!(name: "СССР", code: "ussr")

    card = Card.create!(
      code: "test_card",
      nation: nation,
      name: "Т-34",
      card_type: "technique",
      weight: 1,
      price: 2
    )

    technique = Technique.create!(
      card: card,
      technique_type: "medium_tank",
      attack_range: 1,
      movement_count: 1,
      movement_type: "diagonal",
      firepower: 3,
      hp: 10,
      fuel: 1
    )

    assert_equal technique, card.technique
  end

  test "has many abilities through card abilities" do
    nation = Nation.create!(name: "СССР", code: "ussr")

    card = Card.create!(
      code: "test_card",
      nation: nation,
      name: "Артиллерия",
      card_type: "order",
      weight: 1,
      price: 2
    )

    ability = Ability.create!(
      name: "Нанесение урона",
      code: "damage_technique"
    )

    CardAbility.create!(
      card: card,
      ability: ability,
      parameters: { "damage" => 3 }
    )

    assert_includes card.abilities, ability
  end

  test "requires name" do
    nation = Nation.create!(name: "СССР", code: "ussr")

    card = Card.new(
      nation: nation,
      card_type: "technique",
      weight: 1,
      price: 2
    )

    assert_not card.valid?
    assert_includes card.errors[:name], "can't be blank"
  end

  test "requires card type" do
    nation = Nation.create!(name: "СССР", code: "ussr")

    card = Card.new(
      nation: nation,
      name: "Т-34",
      weight: 1,
      price: 2
    )

    assert_not card.valid?
    assert_includes card.errors[:card_type], "can't be blank"
  end

  test "requires positive integer weight" do
    nation = Nation.create!(name: "СССР", code: "ussr")

    card = Card.new(
      nation: nation,
      name: "Т-34",
      card_type: "technique",
      weight: 0,
      price: 2
    )

    assert_not card.valid?
    assert card.errors[:weight].any?
  end

  test "requires price" do
    nation = Nation.create!(name: "СССР", code: "ussr")

    card = Card.new(
      nation: nation,
      name: "Т-34",
      card_type: "technique",
      weight: 1
    )

    assert_not card.valid?
    assert card.errors[:price].any?
  end

  test "requires non-negative integer price" do
    nation = Nation.create!(name: "СССР", code: "ussr")

    card = Card.new(
      nation: nation,
      name: "Т-34",
      card_type: "technique",
      weight: 1,
      price: -1
    )

    assert_not card.valid?
    assert card.errors[:price].any?
  end

  test "headquarters can have no price" do
    nation = Nation.create!(
      name: "СССР",
      code: "ussr"
    )

    card = Card.new(
      code: "test_hq",
      nation: nation,
      name: "Test HQ",
      card_type: "headquarters",
      weight: 1,
      price: nil
    )

    assert_predicate card, :valid?
  end

  test "requires code" do
    nation = Nation.create!(name: "Германия", code: "germany")

    card = Card.new(
      name: "Test Card",
      card_type: "order",
      weight: 1,
      price: 1,
      nation: nation
    )

    assert_not card.valid?
    assert_includes card.errors[:code], "can't be blank"
  end

  test "requires unique code" do
    nation = Nation.create!(name: "Германия", code: "germany")

    Card.create!(
      code: "test_card",
      name: "Existing Card",
      card_type: "order",
      weight: 1,
      price: 1,
      nation: nation
    )

    card = Card.new(
      code: "test_card",
      name: "Another Card",
      card_type: "order",
      weight: 1,
      price: 1,
      nation: nation
    )

    assert_not card.valid?
    assert_includes card.errors[:code], "has already been taken"
  end
end
