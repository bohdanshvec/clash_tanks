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

  test "does not allow playing order without abilities" do
    @state["players"][PLAYER_ID.to_s]["hand"] = [
      {
        "card_id" => 20,
        "name" => "Приказ",
        "card_type" => "order",
        "nation_id" => 10,
        "weight" => 1,
        "price" => 2,
        "abilities" => []
      }
    ]

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 20
      }
    )

    result = GameEngine::Actions::PlayCard.new(@state, action).call

    assert_not result.success?
    assert_equal "Order has no abilities", result.error
  end

  test "plays order and executes its ability" do
    @state["field"][1][2] = enemy_technique

    @state["players"][PLAYER_ID.to_s]["hand"] = [
      order_card(
        card_id: 20,
        name: "Приказ",
        abilities: [
          {
            "code" => "damage_technique",
            "damage" => 3
          }
        ]
      )
    ]

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 20,
        targets: [
          { row: 1, column: 2 }
        ]
      }
    )

    result = GameEngine::Actions::PlayCard.new(@state, action).call

    assert result.success?
    assert_equal 7, result.state["field"][1][2]["hp"]
  end

  test "deducts order price after successful execution" do
    @state["field"][1][2] = enemy_technique

    @state["players"][PLAYER_ID.to_s]["hand"] = [
      order_card(
        card_id: 20,
        name: "Приказ",
        abilities: [
          {
            "code" => "damage_technique",
            "damage" => 3
          }
        ]
      )
    ]

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 20,
        targets: [
          { row: 1, column: 2 }
        ]
      }
    )

    result = GameEngine::Actions::PlayCard.new(@state, action).call

    assert result.success?
    assert_equal 3, result.state["players"][PLAYER_ID.to_s]["resources"]
  end

  test "moves order to graveyard after successful execution" do
    @state["field"][1][2] = enemy_technique

    order = order_card(
      card_id: 20,
      name: "Приказ",
      abilities: [
        {
          "code" => "damage_technique",
          "damage" => 3
        }
      ]
    )

    @state["players"][PLAYER_ID.to_s]["hand"] = [order]

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 20,
        targets: [
          { row: 1, column: 2 }
        ]
      }
    )

    result = GameEngine::Actions::PlayCard.new(@state, action).call

    assert result.success?

    player = result.state["players"][PLAYER_ID.to_s]

    assert_empty player["hand"]
    assert_equal 1, player["graveyard"].size
    assert_equal order, player["graveyard"].first
  end

  test "does not play order when its ability fails" do
    order = order_card(
      card_id: 20,
      name: "Приказ",
      abilities: [
        {
          "code" => "damage_technique",
          "damage" => 3
        }
      ]
    )

    @state["players"][PLAYER_ID.to_s]["hand"] = [order]

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 20,
        targets: [
          { row: 1, column: 2 }
        ]
      }
    )

    result = GameEngine::Actions::PlayCard.new(@state, action).call

    assert_not result.success?
    assert_equal 5, @state["players"][PLAYER_ID.to_s]["resources"]
    assert_equal [order], @state["players"][PLAYER_ID.to_s]["hand"]
    assert_empty @state["players"][PLAYER_ID.to_s]["graveyard"]
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

  test "executes multiple order abilities in sequence" do
    @state["field"][1][2] = enemy_technique

    @state["players"][PLAYER_ID.to_s]["hand"] = [
      order_card(
        card_id: 20,
        name: "Двойной удар",
        abilities: [
          {
            "code" => "damage_technique",
            "damage" => 3
          },
          {
            "code" => "damage_technique",
            "damage" => 2
          }
        ]
      )
    ]

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 20,
        targets: [
          { row: 1, column: 2 }
        ]
      }
    )

    result = GameEngine::Actions::PlayCard.new(@state, action).call

    assert result.success?
    assert_equal 5, result.state["field"][1][2]["hp"]
  end

  test "does not apply order when a later ability fails" do
    @state["field"][1][2] = enemy_technique

    order = order_card(
      card_id: 20,
      name: "Приказ",
      abilities: [
        {
          "code" => "damage_technique",
          "damage" => 3
        },
        {
          "code" => "unknown_ability",
          "damage" => 2
        }
      ]
    )

    @state["players"][PLAYER_ID.to_s]["hand"] = [order]

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 20,
        targets: [
          { row: 1, column: 2 }
        ]
      }
    )

    result = GameEngine::Actions::PlayCard.new(@state, action).call

    assert_not result.success?
    assert_equal "Unknown ability", result.error

    assert_equal 10, @state["field"][1][2]["hp"]
    assert_equal 5, @state["players"][PLAYER_ID.to_s]["resources"]
    assert_equal [order], @state["players"][PLAYER_ID.to_s]["hand"]
    assert_empty @state["players"][PLAYER_ID.to_s]["graveyard"]
  end

  test "plays platoon to the first platoon slot" do
    platoon = platoon_card

    @state["players"][PLAYER_ID.to_s]["hand"] = [platoon]

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 40
      }
    )

    result = GameEngine::Actions::PlayCard.new(@state, action).call

    assert result.success?

    slots = result.state["players"][PLAYER_ID.to_s]["platoons"]
    played_platoon = slots[0]

    assert_equal "platoon", played_platoon["type"]
    assert_equal 40, played_platoon["card_id"]
    assert_equal PLAYER_ID, played_platoon["player_id"]
    assert_equal 10, played_platoon["nation_id"]
    assert_equal "Пехотный взвод", played_platoon["name"]
    assert_equal 5, played_platoon["firepower"]
    assert_equal 10, played_platoon["hp"]
    assert_equal 3, played_platoon["armor"]
    assert_equal 2, played_platoon["fuel"]

    assert_nil slots[1]
    assert_nil slots[2]
    assert_nil slots[3]
  end

  test "removes played platoon from hand" do
    @state["players"][PLAYER_ID.to_s]["hand"] = [platoon_card]

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 40
      }
    )

    result = GameEngine::Actions::PlayCard.new(@state, action).call

    assert result.success?
    assert_empty result.state["players"][PLAYER_ID.to_s]["hand"]
  end

  test "deducts platoon price from player's resources" do
    @state["players"][PLAYER_ID.to_s]["hand"] = [
      platoon_card(price: 3)
    ]

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 40
      }
    )

    result = GameEngine::Actions::PlayCard.new(@state, action).call

    assert result.success?
    assert_equal 2, result.state["players"][PLAYER_ID.to_s]["resources"]
  end

  test "plays second platoon to the second slot" do
    @state["players"][PLAYER_ID.to_s]["hand"] = [
      platoon_card(card_id: 40, name: "Первый взвод"),
      platoon_card(card_id: 41, name: "Второй взвод")
    ]

    first_action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 40
      }
    )

    first_result = GameEngine::Actions::PlayCard.new(@state, first_action).call

    assert first_result.success?

    second_action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 41
      }
    )

    second_result = GameEngine::Actions::PlayCard.new(
      first_result.state,
      second_action
    ).call

    assert second_result.success?

    slots = second_result.state["players"][PLAYER_ID.to_s]["platoons"]

    assert_equal 40, slots[0]["card_id"]
    assert_equal 41, slots[1]["card_id"]
    assert_nil slots[2]
    assert_nil slots[3]
  end

  test "plays platoon to the first free slot" do
    player = @state["players"][PLAYER_ID.to_s]

    player["platoons"] = [
      nil,
      platoon_object_for_test(card_id: 41),
      nil,
      platoon_object_for_test(card_id: 43)
    ]

    player["hand"] = [platoon_card(card_id: 40)]

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 40
      }
    )

    result = GameEngine::Actions::PlayCard.new(@state, action).call

    assert result.success?

    slots = result.state["players"][PLAYER_ID.to_s]["platoons"]

    assert_equal 40, slots[0]["card_id"]
    assert_equal 41, slots[1]["card_id"]
    assert_nil slots[2]
    assert_equal 43, slots[3]["card_id"]
  end

  test "does not allow playing platoon when all slots are occupied" do
    player = @state["players"][PLAYER_ID.to_s]

    player["platoons"] = [
      platoon_object_for_test(card_id: 41),
      platoon_object_for_test(card_id: 42),
      platoon_object_for_test(card_id: 43),
      platoon_object_for_test(card_id: 44)
    ]

    platoon = platoon_card(card_id: 40)
    player["hand"] = [platoon]

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 40
      }
    )

    result = GameEngine::Actions::PlayCard.new(@state, action).call

    assert_not result.success?
    assert_equal "No free platoon slot", result.error

    assert_equal [platoon], player["hand"]
    assert_equal 5, player["resources"]

    assert_equal 41, player["platoons"][0]["card_id"]
    assert_equal 42, player["platoons"][1]["card_id"]
    assert_equal 43, player["platoons"][2]["card_id"]
    assert_equal 44, player["platoons"][3]["card_id"]
  end

  test "does not modify original state when playing platoon" do
    platoon = platoon_card
    player = @state["players"][PLAYER_ID.to_s]

    player["hand"] = [platoon]
    player["resources"] = 5
    player["platoons"] = [
      nil,
      platoon_object_for_test(card_id: 41),
      nil,
      nil
    ]

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 40
      }
    )

    result = GameEngine::Actions::PlayCard.new(@state, action).call

    assert result.success?

    assert_equal [platoon], player["hand"]
    assert_equal 5, player["resources"]

    assert_nil player["platoons"][0]
    assert_equal 41, player["platoons"][1]["card_id"]
    assert_nil player["platoons"][2]
    assert_nil player["platoons"][3]
  end

  test "does not move played platoon to graveyard" do
    player = @state["players"][PLAYER_ID.to_s]
    player["hand"] = [platoon_card]

    action = GameEngine::Action.new(
      player_id: PLAYER_ID,
      type: "play_card",
      payload: {
        card_id: 40
      }
    )

    result = GameEngine::Actions::PlayCard.new(@state, action).call

    assert result.success?

    assert_empty result.state["players"][PLAYER_ID.to_s]["hand"]
    assert_empty result.state["players"][PLAYER_ID.to_s]["graveyard"]
    assert_equal 40, result.state["players"][PLAYER_ID.to_s]["platoons"][0]["card_id"]
  end

  private

  def platoon_card(
    card_id: 40,
    name: "Пехотный взвод",
    price: 2,
    firepower: 5,
    hp: 10,
    armor: 3,
    fuel: 2
  )
    {
      "card_id" => card_id,
      "name" => name,
      "card_type" => "platoon",
      "nation_id" => 10,
      "weight" => 1,
      "price" => price,
      "platoon" => {
        "firepower" => firepower,
        "hp" => hp,
        "armor" => armor,
        "fuel" => fuel
      }
    }
  end

  def platoon_object_for_test(
    card_id:,
    name: "Пехотный взвод",
    firepower: 5,
    hp: 10,
    armor: 3,
    fuel: 2
  )
    {
      "type" => "platoon",
      "card_id" => card_id,
      "player_id" => PLAYER_ID,
      "nation_id" => 10,
      "name" => name,
      "firepower" => firepower,
      "hp" => hp,
      "armor" => armor,
      "fuel" => fuel
    }
  end

  def order_card(card_id:, name:, abilities:)
    {
      "card_id" => card_id,
      "name" => name,
      "card_type" => "order",
      "nation_id" => 10,
      "weight" => 1,
      "price" => 2,
      "abilities" => abilities
    }
  end

  def enemy_technique
    {
      "type" => "technique",
      "card_id" => 30,
      "player_id" => OPPONENT_ID,
      "nation_id" => 20,
      "name" => "Т-34",
      "technique_type" => "medium_tank",
      "hp" => 10,
      "firepower" => 4,
      "fuel" => 2,
      "attack_range" => 1,
      "movement_count" => 1,
      "movement_type" => "diagonal",
      "has_attacked" => false,
      "has_counterattacked" => false
    }
  end
end
