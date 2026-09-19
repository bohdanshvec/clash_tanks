require "test_helper"

class AbilityTest < ActiveSupport::TestCase
  test "has many cards through card abilities" do
    ussr = Nation.create!(name: "СССР", code: "ussr")
    germany = Nation.create!(name: "Германия", code: "germany")

    t34 = Card.create!(
      code: "test_t34",
      nation: ussr,
      name: "Т-34",
      card_type: "technique",
      weight: 1,
      price: 2
    )

    panther = Card.create!(
      code: "test_panther",
      nation: germany,
      name: "Panther",
      card_type: "technique",
      weight: 1,
      price: 3
    )

    ability = Ability.create!(
      name: "Диагональное перемещение",
      code: "diagonal_movement"
    )

    CardAbility.create!(card: t34, ability: ability)
    CardAbility.create!(card: panther, ability: ability)

    assert_includes ability.cards, t34
    assert_includes ability.cards, panther
  end

  test "requires name" do
    ability = Ability.new(code: "first_attack")

    assert_not ability.valid?
    assert_includes ability.errors[:name], "can't be blank"
  end

  test "requires code" do
    ability = Ability.new(name: "Первый выстрел")

    assert_not ability.valid?
    assert_includes ability.errors[:code], "can't be blank"
  end

  test "requires unique code" do
    Ability.create!(
      name: "Первый выстрел",
      code: "first_attack"
    )

    ability = Ability.new(
      name: "Другая способность",
      code: "first_attack"
    )

    assert_not ability.valid?
    assert_includes ability.errors[:code], "has already been taken"
  end
end
