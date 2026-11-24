require "test_helper"

class GameEngine::Abilities::Techniques::HeadquartersDefenderTest < ActiveSupport::TestCase
  test "defines headquarters defender ability code" do
    assert_equal(
      "headquarters_defender",
      GameEngine::Abilities::Techniques::HeadquartersDefender::CODE
    )
  end

  test "provides ability description" do
    assert_equal(
      "Приймає урон штабу на плацдармі.",
      GameEngine::Abilities::Techniques::HeadquartersDefender.description
    )
  end
end