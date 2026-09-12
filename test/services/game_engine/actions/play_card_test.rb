require "test_helper"

class GameEngine::Actions::PlayCardTest < ActiveSupport::TestCase
  PLAYER_ID = 1
  OPPONENT_ID = 2

  def setup
    @state = GameEngine::GameState.initial(
      current_player_id: PLAYER_ID,
      participants: [
        { player_id: PLAYER_ID, nation_id: 10 },
        { player_id: OPPONENT_ID, nation_id: 20 }
      ]
    )

    @state["players"][PLAYER_ID.to_s]["resources"] = 5

    @state["players"][PLAYER_ID.to_s]["hand"] = [
      {
        "card_id" => 15,
        "name" => "Т-34",
        "card_type" => "technique",
        "nation_id" => 10,
        "weight" => 1,
        "price" => 2,
        "technique" => {
          "technique_type" => "medium_tank",
          "attack_range" => 1,
          "movement_count" => 1,
          "movement_type" => "diagonal",
          "firepower" => 4,
          "hp" => 10,
          "fuel" => 2
        }
      }
    ]
  end

  test "plays technique to a free cell adjacent to player's headquarters" do
    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 15,
        row: 1,
        column: 0
      }
    )

    result = GameEngine::Actions::PlayCard.new(@state, action).call

    assert result.success?

    technique = result.state["field"][1][0]

    assert_equal "technique", technique["type"]
    assert_equal 15, technique["card_id"]
    assert_equal PLAYER_ID, technique["player_id"]
    assert_equal 10, technique["nation_id"]
    assert_equal "Т-34", technique["name"]
    assert_equal "medium_tank", technique["technique_type"]
    assert_equal 10, technique["hp"]
    assert_equal 4, technique["firepower"]
    assert_equal 2, technique["fuel"]
    assert_equal 1, technique["attack_range"]
    assert_equal 1, technique["movement_count"]
    assert_equal "diagonal", technique["movement_type"]
    assert_equal false, technique["has_attacked"]
    assert_equal false, technique["has_counterattacked"]
  end

  test "removes played card from hand" do
    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 15,
        row: 1,
        column: 0
      }
    )

    result = GameEngine::Actions::PlayCard.new(@state, action).call

    assert result.success?
    assert_empty result.state["players"][PLAYER_ID.to_s]["hand"]
  end

  test "deducts card price from player's resources" do
    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 15,
        row: 1,
        column: 0
      }
    )

    result = GameEngine::Actions::PlayCard.new(@state, action).call

    assert result.success?
    assert_equal 3, result.state["players"][PLAYER_ID.to_s]["resources"]
  end

  test "plays only one copy when hand contains duplicate cards" do
    card = @state["players"][PLAYER_ID.to_s]["hand"].first
    @state["players"][PLAYER_ID.to_s]["hand"] << card.dup

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 15,
        row: 1,
        column: 0
      }
    )

    result = GameEngine::Actions::PlayCard.new(@state, action).call

    assert result.success?
    assert_equal 1, result.state["players"][PLAYER_ID.to_s]["hand"].size
    assert_equal 15, result.state["players"][PLAYER_ID.to_s]["hand"].first["card_id"]
  end

  test "does not modify original state" do
    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 15,
        row: 1,
        column: 0
      }
    )

    result = GameEngine::Actions::PlayCard.new(@state, action).call

    assert result.success?
    assert_equal 1, @state["players"][PLAYER_ID.to_s]["hand"].size
    assert_equal 5, @state["players"][PLAYER_ID.to_s]["resources"]
    assert_nil @state["field"][1][0]
  end

  test "does not allow playing when it is not player's turn" do
    @state["current_player_id"] = OPPONENT_ID

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 15,
        row: 1,
        column: 0
      }
    )

    result = GameEngine::Actions::PlayCard.new(@state, action).call

    assert_not result.success?
    assert_equal "It is not player's turn", result.error
  end

  test "does not allow playing card that is not in hand" do
    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 999,
        row: 1,
        column: 0
      }
    )

    result = GameEngine::Actions::PlayCard.new(@state, action).call

    assert_not result.success?
    assert_equal "Card is not in hand", result.error
  end

  test "does not allow playing order as technique" do
    @state["players"][PLAYER_ID.to_s]["hand"] = [
      {
        "card_id" => 20,
        "name" => "Приказ",
        "card_type" => "order",
        "nation_id" => 10,
        "weight" => 1,
        "price" => 2
      }
    ]

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 20,
        row: 1,
        column: 0
      }
    )

    result = GameEngine::Actions::PlayCard.new(@state, action).call

    assert_not result.success?
    assert_equal "Card is not a technique", result.error
  end

  test "does not allow playing card without enough resources" do
    @state["players"][PLAYER_ID.to_s]["resources"] = 1

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 15,
        row: 1,
        column: 0
      }
    )

    result = GameEngine::Actions::PlayCard.new(@state, action).call

    assert_not result.success?
    assert_equal "Not enough resources", result.error
  end

  test "does not allow playing to occupied cell" do
    @state["field"][1][0] = {
      "type" => "technique",
      "card_id" => 20,
      "player_id" => OPPONENT_ID
    }

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 15,
        row: 1,
        column: 0
      }
    )

    result = GameEngine::Actions::PlayCard.new(@state, action).call

    assert_not result.success?
    assert_equal "Destination cell is occupied", result.error
  end

  test "does not allow playing outside the field" do
    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 15,
        row: 3,
        column: 0
      }
    )

    result = GameEngine::Actions::PlayCard.new(@state, action).call

    assert_not result.success?
    assert_equal "Invalid coordinates", result.error
  end

  test "does not allow playing technique outside headquarters adjacent cells" do
    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 15,
        row: 0,
        column: 1
      }
    )

    result = GameEngine::Actions::PlayCard.new(@state, action).call

    assert_not result.success?
    assert_equal "Technique must be placed adjacent to headquarters", result.error
  end

  test "does not allow playing technique adjacent to enemy headquarters" do
    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 15,
        row: 1,
        column: 4
      }
    )

    result = GameEngine::Actions::PlayCard.new(@state, action).call

    assert_not result.success?
    assert_equal "Technique must be placed adjacent to headquarters", result.error
  end
end
