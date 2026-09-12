require "test_helper"

class TechniqueAbilityTest < ActiveSupport::TestCase
  test "technique association works" do
    nation = Nation.create!(name: "СССР", code: "ussr")
    card = Card.create!(
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
      hp: 5,
      fuel: 1
    )

    ability = Ability.create!(
      name: "Первый выстрел",
      code: "first_attack"
    )

    technique_ability = TechniqueAbility.create!(
      technique: technique,
      ability: ability
    )

    assert_equal technique, technique_ability.technique
  end

  test "ability association works" do
    nation = Nation.create!(name: "СССР", code: "ussr")
    card = Card.create!(
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
      hp: 5,
      fuel: 1
    )

    ability = Ability.create!(
      name: "Первый выстрел",
      code: "first_attack"
    )

    technique_ability = TechniqueAbility.create!(
      technique: technique,
      ability: ability
    )

    assert_equal ability, technique_ability.ability
  end

  test "cannot duplicate the same technique and ability pair" do
    nation = Nation.create!(name: "СССР", code: "ussr")
    card = Card.create!(
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
      hp: 5,
      fuel: 1
    )

    ability = Ability.create!(
      name: "Первый выстрел",
      code: "first_attack"
    )

    TechniqueAbility.create!(
      technique: technique,
      ability: ability
    )

    assert_raises(ActiveRecord::RecordNotUnique) do
      TechniqueAbility.create!(
        technique: technique,
        ability: ability
      )
    end
  end
end
