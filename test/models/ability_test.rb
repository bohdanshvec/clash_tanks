require "test_helper"

class AbilityTest < ActiveSupport::TestCase
  test "has many techniques through technique abilities" do
    ussr = Nation.create!(name: "СССР", code: "ussr")
    germany = Nation.create!(name: "Германия", code: "germany")

    t34_card = Card.create!(
      nation: ussr,
      name: "Т-34",
      card_type: "technique",
      weight: 1
    )

    panther_card = Card.create!(
      nation: germany,
      name: "Panther",
      card_type: "technique",
      weight: 1
    )

    t34 = Technique.create!(card: t34_card)
    panther = Technique.create!(card: panther_card)

    ability = Ability.create!(
      name: "Диагональное перемещение",
      code: "diagonal_movement"
    )

    TechniqueAbility.create!(technique: t34, ability: ability)
    TechniqueAbility.create!(technique: panther, ability: ability)

    assert_includes ability.techniques, t34
    assert_includes ability.techniques, panther
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
