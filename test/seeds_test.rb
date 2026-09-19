require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  setup do
    load Rails.root.join("db/seeds.rb")
  end

  test "creates base game content" do
    assert_equal 3, Nation.count
    assert_equal 2, Ability.count
    assert_equal 33, Card.count
    assert_equal 18, Technique.count
    assert_equal 6, Platoon.count
    assert_equal 3, Headquarters.count
    assert_equal 6, CardAbility.count
  end

  test "creates all nations" do
    assert_equal %w[germany usa ussr], Nation.order(:code).pluck(:code)
  end

  test "creates all abilities" do
    assert_equal %w[damage_technique draw_cards], Ability.order(:code).pluck(:code)
  end

  test "creates three headquarters" do
    assert_equal 3, Card.where(card_type: "headquarters").count
    assert_equal 3, Headquarters.count
  end

  test "creates eighteen techniques" do
    assert_equal 18, Card.where(card_type: "technique").count
    assert_equal 18, Technique.count
  end

  test "creates six orders" do
    assert_equal 6, Card.where(card_type: "order").count
  end

  test "creates six platoons" do
    assert_equal 6, Card.where(card_type: "platoon").count
    assert_equal 6, Platoon.count
  end

  test "creates six card abilities" do
    assert_equal 6, CardAbility.count
  end

  test "seed is idempotent" do
    assert_nothing_raised do
      load Rails.root.join("db/seeds.rb")
    end

    assert_equal 3, Nation.count
    assert_equal 2, Ability.count
    assert_equal 33, Card.count
    assert_equal 18, Technique.count
    assert_equal 6, Platoon.count
    assert_equal 3, Headquarters.count
    assert_equal 6, CardAbility.count
  end
end
