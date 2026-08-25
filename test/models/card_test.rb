require "test_helper"

class CardTest < ActiveSupport::TestCase
  test "belongs to nation" do
    nation = Nation.create!(name: "СССР", code: "ussr")
    card = Card.create!(
      nation: nation,
      name: "Т-34",
      card_type: "technique",
      weight: 1
    )

    assert_equal nation, card.nation
  end

  test "has one technique" do
    nation = Nation.create!(name: "СССР", code: "ussr")
    card = Card.create!(
      nation: nation,
      name: "Т-34",
      card_type: "technique",
      weight: 1
    )
    technique = Technique.create!(card: card)

    assert_equal technique, card.technique
  end
  
  test "requires name" do
		nation = Nation.create!(name: "СССР", code: "ussr")
		card = Card.new(
		  nation: nation,
		  card_type: "technique",
		  weight: 1
		)

		assert_not card.valid?
		assert_includes card.errors[:name], "can't be blank"
	end

	test "requires card type" do
		nation = Nation.create!(name: "СССР", code: "ussr")
		card = Card.new(
		  nation: nation,
		  name: "Т-34",
		  weight: 1
		)

		assert_not card.valid?
		assert_includes card.errors[:card_type], "can't be blank"
	end

	test "requires weight" do
		nation = Nation.create!(name: "СССР", code: "ussr")
		card = Card.new(
		  nation: nation,
		  name: "Т-34",
		  card_type: "technique"
		)

		assert_not card.valid?
		assert_includes card.errors[:weight], "can't be blank"
	end

	test "weight must be an integer greater than zero" do
		nation = Nation.create!(name: "СССР", code: "ussr")

		zero_weight = Card.new(
		  nation: nation,
		  name: "Т-34",
		  card_type: "technique",
		  weight: 0
		)

		negative_weight = Card.new(
		  nation: nation,
		  name: "Panther",
		  card_type: "technique",
		  weight: -1
		)

		decimal_weight = Card.new(
		  nation: nation,
		  name: "Sherman",
		  card_type: "technique",
		  weight: 1.5
		)

		assert_not zero_weight.valid?
		assert_not negative_weight.valid?
		assert_not decimal_weight.valid?
	end
end
