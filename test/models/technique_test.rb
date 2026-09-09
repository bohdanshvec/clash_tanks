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

    technique = Technique.create!(
      card: card,
      technique_type: "medium_tank",
      attack_range: 1,
      movement_count: 1,
      movement_type: "diagonal"
    )

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

    technique = Technique.create!(
      card: card,
      technique_type: "medium_tank",
      attack_range: 1,
      movement_count: 1,
      movement_type: "diagonal"
    )

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

  test "validates technique type" do
    nation = Nation.create!(name: "СССР", code: "ussr")
    card = Card.create!(
      nation: nation,
      name: "Т-34",
      card_type: "technique",
      weight: 1
    )

    technique = Technique.new(
      card: card,
      technique_type: "invalid",
      attack_range: 1,
      movement_count: 1,
      movement_type: "orthogonal"
    )

    assert_not technique.valid?
    assert_includes technique.errors[:technique_type], "is not included in the list"
  end
  
  test "accepts all technique types" do
		nation = Nation.create!(name: "СССР", code: "ussr")
		card = Card.create!(
		  nation: nation,
		  name: "Т-34",
		  card_type: "technique",
		  weight: 1
		)

		Technique::TECHNIQUE_TYPES.each do |technique_type|
		  technique = Technique.new(
		    card: card,
		    technique_type: technique_type,
		    attack_range: 1,
		    movement_count: 1,
		    movement_type: "orthogonal"
		  )

		  assert technique.valid?, "Expected #{technique_type} to be valid"
		end
	end

	test "rejects invalid movement type" do
		nation = Nation.create!(name: "СССР", code: "ussr")
		card = Card.create!(
		  nation: nation,
		  name: "Т-34",
		  card_type: "technique",
		  weight: 1
		)

		technique = Technique.new(
		  card: card,
		  technique_type: "medium_tank",
		  attack_range: 1,
		  movement_count: 1,
		  movement_type: "invalid"
		)

		assert_not technique.valid?
		assert_includes technique.errors[:movement_type], "is not included in the list"
	end

	test "accepts orthogonal and diagonal movement types" do
		nation = Nation.create!(name: "СССР", code: "ussr")
		card = Card.create!(
		  nation: nation,
		  name: "Т-34",
		  card_type: "technique",
		  weight: 1
		)

		Technique::MOVEMENT_TYPES.each do |movement_type|
		  technique = Technique.new(
		    card: card,
		    technique_type: "medium_tank",
		    attack_range: 1,
		    movement_count: 1,
		    movement_type: movement_type
		  )

		  assert technique.valid?, "Expected #{movement_type} to be valid"
		end
	end
	
	test "attack range must be a positive integer" do
		nation = Nation.create!(name: "СССР", code: "ussr")
		card = Card.create!(
		  nation: nation,
		  name: "Т-34",
		  card_type: "technique",
		  weight: 1
		)

		zero_range = Technique.new(
		  card: card,
		  technique_type: "medium_tank",
		  attack_range: 0,
		  movement_count: 1,
		  movement_type: "diagonal"
		)

		negative_range = Technique.new(
		  card: card,
		  technique_type: "medium_tank",
		  attack_range: -1,
		  movement_count: 1,
		  movement_type: "diagonal"
		)

		decimal_range = Technique.new(
		  card: card,
		  technique_type: "medium_tank",
		  attack_range: 1.5,
		  movement_count: 1,
		  movement_type: "diagonal"
		)

		assert_not zero_range.valid?
		assert_not negative_range.valid?
		assert_not decimal_range.valid?
	end

	test "movement count must be a positive integer" do
		nation = Nation.create!(name: "СССР", code: "ussr")
		card = Card.create!(
		  nation: nation,
		  name: "Т-34",
		  card_type: "technique",
		  weight: 1
		)

		zero_count = Technique.new(
		  card: card,
		  technique_type: "medium_tank",
		  attack_range: 1,
		  movement_count: 0,
		  movement_type: "diagonal"
		)

		negative_count = Technique.new(
		  card: card,
		  technique_type: "medium_tank",
		  attack_range: 1,
		  movement_count: -1,
		  movement_type: "diagonal"
		)

		decimal_count = Technique.new(
		  card: card,
		  technique_type: "medium_tank",
		  attack_range: 1,
		  movement_count: 1.5,
		  movement_type: "diagonal"
		)

		assert_not zero_count.valid?
		assert_not negative_count.valid?
		assert_not decimal_count.valid?
	end
	
	test "technique types have correct movement characteristics" do
		expected = {
		  "light_tank" => {
		    movement_type: "orthogonal",
		    movement_count: 2
		  },
		  "medium_tank" => {
		    movement_type: "diagonal",
		    movement_count: 1
		  },
		  "heavy_tank" => {
		    movement_type: "orthogonal",
		    movement_count: 1
		  },
		  "tank_destroyer" => {
		    movement_type: "orthogonal",
		    movement_count: 1
		  },
		  "artillery" => {
		    movement_type: "orthogonal",
		    movement_count: 1
		  }
		}

		expected.each do |technique_type, characteristics|
		  nation = Nation.create!(
		    name: "СССР",
		    code: "ussr_#{technique_type}"
		  )

		  card = Card.create!(
		    nation: nation,
		    name: technique_type,
		    card_type: "technique",
		    weight: 1
		  )

		  technique = Technique.create!(
		    card: card,
		    technique_type: technique_type,
		    attack_range: 1,
		    movement_count: characteristics[:movement_count],
		    movement_type: characteristics[:movement_type]
		  )

		  assert_equal characteristics[:movement_type], technique.movement_type
		  assert_equal characteristics[:movement_count], technique.movement_count
		end
end
end
