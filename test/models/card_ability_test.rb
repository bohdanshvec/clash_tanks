require "test_helper"

class CardAbilityTest < ActiveSupport::TestCase
  setup do
    @nation = Nation.create!(
      name: "СССР",
      code: "ussr"
    )

    @card = Card.create!(
      nation: @nation,
      name: "Артиллерия",
      card_type: "order",
      weight: 1,
      price: 2
    )

    @ability = Ability.create!(
      name: "Нанесение урона",
      code: "damage_technique"
    )
  end

  test "belongs to card" do
    card_ability = CardAbility.create!(
      card: @card,
      ability: @ability
    )

    assert_equal @card, card_ability.card
  end

  test "belongs to ability" do
    card_ability = CardAbility.create!(
      card: @card,
      ability: @ability
    )

    assert_equal @ability, card_ability.ability
  end

  test "stores ability parameters" do
    card_ability = CardAbility.create!(
      card: @card,
      ability: @ability,
      parameters: { "damage" => 3 }
    )

    assert_equal(
      { "damage" => 3 },
      card_ability.parameters
    )
  end

  test "does not allow the same ability twice for one card" do
    CardAbility.create!(
      card: @card,
      ability: @ability
    )

    duplicate = CardAbility.new(
      card: @card,
      ability: @ability
    )

    refute duplicate.valid?
    assert_includes duplicate.errors[:card_id], "has already been taken"
  end

  test "allows the same ability for different cards" do
    second_card = Card.create!(
      nation: @nation,
      name: "Т-34",
      card_type: "technique",
      weight: 1,
      price: 2
    )

    CardAbility.create!(
      card: @card,
      ability: @ability
    )

    second_card_ability = CardAbility.create!(
      card: second_card,
      ability: @ability
    )

    assert_equal second_card, second_card_ability.card
    assert_equal @ability, second_card_ability.ability
  end
end
