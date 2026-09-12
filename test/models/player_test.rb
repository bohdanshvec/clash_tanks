require "test_helper"

class PlayerTest < ActiveSupport::TestCase
  test "has many decks" do
    player = Player.create!
    nation = Nation.create!(name: "СССР", code: "ussr")

    deck = Deck.create!(
      player: player,
      nation: nation,
      name: "Основная колода"
    )

    assert_includes player.decks, deck
  end
end
