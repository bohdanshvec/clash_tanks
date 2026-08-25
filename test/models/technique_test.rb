require "test_helper"

class TechniqueTest < ActiveSupport::TestCase
  test "belongs to card" do
    nation = Nation.create!(name: "СССР", code: "ussr")
    card = Card.create!(
      nation: nation,
      name: "Т-34",
      card_type: "technique",
      weight: 1
    )
    technique = Technique.create!(card: card)

    assert_equal card, technique.card
  end

  test "has many abilities through technique abilities" do
    nation = Nation.create!(name: "СССР", code: "ussr")
    card = Card.create!(
      nation: nation,
      name: "Т-34",
      card_type: "technique",
      weight: 1
    )
    technique = Technique.create!(card: card)

    ability = Ability.create!(
      name: "Диагональное перемещение",
      code: "diagonal_movement"
    )

    TechniqueAbility.create!(
      technique: technique,
      ability: ability
    )

    assert_includes technique.abilities, ability
  end
end
