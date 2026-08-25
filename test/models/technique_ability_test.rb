require "test_helper"

class TechniqueAbilityTest < ActiveSupport::TestCase
  test "belongs to technique" do
    nation = Nation.create!(name: "СССР", code: "ussr")
    card = Card.create!(
      nation: nation,
      name: "Т-34",
      card_type: "technique",
      weight: 1
    )
    technique = Technique.create!(card: card)

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

  test "belongs to ability" do
    nation = Nation.create!(name: "СССР", code: "ussr")
    card = Card.create!(
      nation: nation,
      name: "Т-34",
      card_type: "technique",
      weight: 1
    )
    technique = Technique.create!(card: card)

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
      weight: 1
    )
    technique = Technique.create!(card: card)

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
