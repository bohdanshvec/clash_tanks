require "test_helper"

class ApplicationHelperTest < ActiveSupport::TestCase
  include ApplicationHelper

  test "describes damage technique ability" do
    assert_equal(
      "Завдає техніці 3 од. шкоди",
      ability_description(
        code: GameEngine::Abilities::Orders::DamageTechnique::CODE,
        parameters: { "damage" => 3 }
      )
    )
  end

  test "describes draw cards ability" do
    assert_equal(
      "Добрати карт: 2",
      ability_description(
        code: GameEngine::Abilities::Orders::DrawCards::CODE,
        parameters: { "count" => 2 }
      )
    )
  end

  test "describes headquarters defender ability" do
    assert_equal(
      "Приймає урон штабу, знаходячись на плацдармі.",
      ability_description(
        code: GameEngine::Abilities::Techniques::HeadquartersDefender::CODE
      )
    )
  end

  test "returns nil for unknown ability" do
    assert_nil(
      ability_description(
        code: "unknown_ability",
        parameters: {}
      )
    )
  end
end