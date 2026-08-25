require "test_helper"

class NationTest < ActiveSupport::TestCase
  test "has many cards" do
    nation = Nation.create!(name: "СССР", code: "ussr")
    card = Card.create!(
      nation: nation,
      name: "Т-34",
      card_type: "technique",
      weight: 1
    )

    assert_includes nation.cards, card
  end
  
  test "requires name" do
		nation = Nation.new(code: "ussr")

		assert_not nation.valid?
		assert_includes nation.errors[:name], "can't be blank"
	end

	test "requires code" do
		nation = Nation.new(name: "СССР")

		assert_not nation.valid?
		assert_includes nation.errors[:code], "can't be blank"
	end

	test "requires unique code" do
		Nation.create!(name: "СССР", code: "ussr")
		nation = Nation.new(name: "Другая нация", code: "ussr")

		assert_not nation.valid?
		assert_includes nation.errors[:code], "has already been taken"
	end
end
