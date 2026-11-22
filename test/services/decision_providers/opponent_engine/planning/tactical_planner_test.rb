
require "test_helper"

class DecisionProviders::OpponentEngine::Planning::TacticalPlannerTest <
  ActiveSupport::TestCase

  AI_PLAYER_ID = 42
  OPPONENT_ID = 57

  def setup
    @state = GameEngine::GameState.initial(
      current_player_id: AI_PLAYER_ID,
      participants: [
        headquarters_participant(
          player_id: AI_PLAYER_ID,
          nation_id: 10
        ),
        headquarters_participant(
          player_id: OPPONENT_ID,
          nation_id: 20
        )
      ]
    )

    add_headquarters_stats

    @current_time = Time.current + 1.second
  end

  test "returns a plan containing end turn when no other actions are available" do
    @state["field"][2][0]["has_attacked"] = true

    result = plan

    assert_equal 1, result.actions.length
    assert_equal "end_turn", result.actions.first["type"]
    assert_operator result.expanded_nodes, :>=, 1
  end

  test "does not finish the turn when a safe lethal technique attack is available" do
    # Штаб и две другие машины уже использовали свои атаки.
    @state["field"][2][0]["has_attacked"] = true

    first_tank = technique(
      player_id: AI_PLAYER_ID,
      hp: 10,
      firepower: 4
    )
    first_tank["has_attacked"] = true

    second_tank = technique(
      player_id: AI_PLAYER_ID,
      hp: 10,
      firepower: 4
    )
    second_tank["has_attacked"] = true

    third_tank = technique(
      player_id: AI_PLAYER_ID,
      hp: 10,
      firepower: 4
    )

    target = technique(
      player_id: OPPONENT_ID,
      hp: 1,
      firepower: 4
    )
    target["has_counterattacked"] = true

    @state["field"][0][1] = first_tank
    @state["field"][2][1] = second_tank
    @state["field"][1][2] = third_tank
    @state["field"][1][1] = target

    visible_state = visible_state_for_ai

    planner =
      DecisionProviders::OpponentEngine::Planning::TacticalPlanner.new(
        visible_state: visible_state,
        player_id: AI_PLAYER_ID,
        current_time: @current_time,
        depth: 7,
        width: 20
      )

    # Инициализируем внутренние счётчики и профиль,
    # которые обычно создаются в начале TacticalPlanner#call.
    planner.call

    node_class =
      DecisionProviders::OpponentEngine::Planning::TacticalPlanner::Node

    node = node_class.new(
      visible_state: visible_state,
      actions: [],
      steps: [],
      score: 0.0,
      terminal: false
    )

    actions = DecisionProviders::ActionOptions.call(visible_state)

    lethal_attack = {
      "type" => "attack",
      "payload" => {
        "attacker" => [1, 2],
        "target" => [1, 1]
      }
    }

    assert_includes actions, lethal_attack

    assert(
      planner.send(
        :safe_lethal_attack_available?,
        node,
        actions
      )
    )

    # finish_turn не должен добавлять end_turn,
    # пока существует безопасная добивающая атака.
    assert_nil planner.send(:finish_turn, node)
  end

  test "rewards a safe move followed by an attack on enemy headquarters" do
    attacker = technique(
      player_id: AI_PLAYER_ID,
      hp: 10,
      firepower: 4
    )

    @state["field"][1][2] = attacker

    visible_state = visible_state_for_ai

    move_action = {
      "type" => "move",
      "payload" => {
        "from" => [1, 2],
        "to" => [1, 3]
      }
    }

    attack_action = {
      "type" => "attack",
      "payload" => {
        "attacker" => [1, 3],
        "target" => [0, 4]
      }
    }

    moved_state = @state.deep_dup
    moved_state["field"][1][3] = moved_state["field"][1][2]
    moved_state["field"][1][2] = nil

    attacked_state = moved_state.deep_dup
    attacked_state["field"][0][4]["hp"] -= 1

    moved_visible_state = GameEngine::VisibleState.call(
      state: moved_state,
      player_id: AI_PLAYER_ID
    )

    attacked_visible_state = GameEngine::VisibleState.call(
      state: attacked_state,
      player_id: AI_PLAYER_ID
    )

    step_class =
      DecisionProviders::OpponentEngine::Planning::TacticalPlanner::Step

    steps = [
      step_class.new(
        action: move_action,
        expected_visible_state: moved_visible_state
      ),
      step_class.new(
        action: attack_action,
        expected_visible_state: attacked_visible_state
      )
    ]

    planner =
      DecisionProviders::OpponentEngine::Planning::TacticalPlanner.new(
        visible_state: visible_state,
        player_id: AI_PLAYER_ID,
        current_time: @current_time,
        depth: 5,
        width: 10
      )

    bonus = planner.send(
      :safe_headquarters_raid_bonus,
      [move_action, attack_action],
      steps
    )

    assert_equal 8.0, bonus
  end

  test "chooses an attack that destroys an enemy technique" do
    @state["field"][2][0]["has_attacked"] = true

    @state["field"][1][1] = technique(
      player_id: AI_PLAYER_ID,
      hp: 10,
      firepower: 4
    )

    @state["field"][1][2] = technique(
      player_id: OPPONENT_ID,
      hp: 4,
      firepower: 3
    )

    result = plan

    assert_not_empty result.actions
    assert_equal "attack", result.actions.first["type"]

    assert_equal(
      [1, 1],
      result.actions.first.dig("payload", "attacker")
    )

    assert_equal(
      [1, 2],
      result.actions.first.dig("payload", "target")
    )
  end

  test "attacks with headquarters first to protect a vulnerable technique" do
    attacker = technique(
      player_id: AI_PLAYER_ID,
      hp: 4,
      firepower: 8
    )

    target = technique(
      player_id: OPPONENT_ID,
      hp: 12,
      firepower: 4
    )

    @state["field"][1][2] = attacker
    @state["field"][1][1] = target

    result = plan

    assert_operator result.actions.length, :>=, 2

    first_attack = result.actions[0]
    second_attack = result.actions[1]

    assert_equal "attack", first_attack["type"]
    assert_equal [2, 0], first_attack.dig("payload", "attacker")
    assert_equal [1, 1], first_attack.dig("payload", "target")

    assert_equal "attack", second_attack["type"]
    assert_equal [1, 2], second_attack.dig("payload", "attacker")
    assert_equal [1, 1], second_attack.dig("payload", "target")

    # После атаки штабом противник использовал контратаку.
    hq_step_state = result.steps[0].expected_visible_state

    assert(
      hq_step_state.dig("field", 1, 1, "has_counterattacked")
    )

    # Собственная техника не пострадала от первого выстрела.
    assert_equal(
      4,
      hq_step_state.dig("field", 1, 2, "hp")
    )

    # Последующая атака техники уничтожила цель.
    technique_step_state = result.steps[1].expected_visible_state

    assert_nil(
      technique_step_state.dig("field", 1, 1)
    )

    # Техника не получила ответного урона.
    assert_equal(
      4,
      technique_step_state.dig("field", 1, 2, "hp")
    )
  end

  test "uses distant headquarters attack before technique destroys the target without counterattack" do
    attacker = technique(
      player_id: AI_PLAYER_ID,
      hp: 8,
      firepower: 4
    )

    target = technique(
      player_id: OPPONENT_ID,
      hp: 8,
      firepower: 4
    )

    # Наша техника находится рядом с целью и обеспечивает разведку.
    @state["field"][1][3] = attacker
    @state["field"][0][3] = target

    # Штаб находится далеко от цели.
    headquarters_position = [2, 0]
    target_position = [0, 3]
    attacker_position = [1, 3]

    assert_not(
      GameEngine::Rules::Position.adjacent?(
        headquarters_position,
        target_position
      )
    )

    result = plan

    assert_operator result.actions.length, :>=, 2

    headquarters_attack = result.actions[0]
    technique_attack = result.actions[1]

    assert_equal "attack", headquarters_attack["type"]
    assert_equal headquarters_position,
      headquarters_attack.dig("payload", "attacker")
    assert_equal target_position,
      headquarters_attack.dig("payload", "target")

    assert_equal "attack", technique_attack["type"]
    assert_equal attacker_position,
      technique_attack.dig("payload", "attacker")
    assert_equal target_position,
      technique_attack.dig("payload", "target")

    # После дальней атаки штаба цель жива, но ослаблена.
    headquarters_state = result.steps[0].expected_visible_state

    assert_equal 4,
      headquarters_state.dig("field", 0, 3, "hp")

    assert_not(
      headquarters_state.dig(
        "field", 0, 3, "has_counterattacked"
      )
    )

    # Наша техника не получила ответного урона.
    assert_equal 8,
      headquarters_state.dig("field", 1, 3, "hp")

    # Следующая атака уничтожает цель без контратаки.
    final_state = result.steps[1].expected_visible_state

    assert_nil final_state.dig("field", 0, 3)

    assert_equal 8,
      final_state.dig("field", 1, 3, "hp")

    refute(
      result.steps[1].then do |step|
        step.expected_visible_state
          .dig("field", 1, 3, "hp") < 8
      end
    )
  end

  test "continues a two-technique attack after the first tank receives a counterattack" do
    first_tank = technique(
      player_id: AI_PLAYER_ID,
      hp: 10,
      firepower: 4
    )

    second_tank = technique(
      player_id: AI_PLAYER_ID,
      hp: 10,
      firepower: 4
    )

    target = technique(
      player_id: OPPONENT_ID,
      hp: 8,
      firepower: 4
    )

    @state["field"][2][1] = first_tank
    @state["field"][2][3] = second_tank
    @state["field"][1][2] = target

    # Исключаем штаб из числа доступных атакующих.
    @state["field"][2][0]["has_attacked"] = true

    visible_state = visible_state_for_ai

    first_attack = {
      "type" => "attack",
      "payload" => {
      "attacker" => [2, 1],
      "target" => [1, 2]
      }
    }

    simulation =
      DecisionProviders::OpponentEngine::Planning::StateSimulator.call(
        visible_state: visible_state,
        player_id: AI_PLAYER_ID,
        action: first_attack,
        current_time: @current_time
      )

    assert simulation.success?

    state_after_first_attack = simulation.visible_state

    # Первая атака должна вызвать ответную атаку противника.
    assert(
      state_after_first_attack.dig(
        "field", 1, 2, "has_counterattacked"
      )
    )

    # Второй танк должен получить возможность атаковать ту же цель.
    follow_up_actions =
      DecisionProviders::ActionOptions.call(state_after_first_attack)

    assert_includes(
      follow_up_actions,
      {
        "type" => "attack",
        "payload" => {
          "attacker" => [2, 3],
          "target" => [1, 2]
        }
      }
    )

    # Планировщик должен сохранить и выбрать совместную атаку.
    result = plan(visible_state)

    assert_operator result.actions.length, :>=, 2

    first_action, second_action = result.actions.first(2)

    assert_equal "attack", first_action["type"]
    assert_equal "attack", second_action["type"]

    assert_equal(
      [1, 2],
      first_action.dig("payload", "target")
    )

    assert_equal(
      [1, 2],
      second_action.dig("payload", "target")
    )

    refute_equal(
      first_action.dig("payload", "attacker"),
      second_action.dig("payload", "attacker")
    )

    # После второго выстрела цель должна быть уничтожена.
    assert_nil result.steps[1].expected_visible_state.dig(
      "field", 1, 2
    )
  end

  test "chooses a profitable ranged attack by a single technique" do
    @state["field"][2][0]["has_attacked"] = true

    attacker = technique(
      player_id: AI_PLAYER_ID,
      hp: 10,
      firepower: 4
    )
    attacker["attack_range"] = 2

    target = technique(
      player_id: OPPONENT_ID,
      hp: 10,
      firepower: 4
    )
    target["movement_count"] = 0
    target["movement_limit"] = 0

    @state["field"][1][1] = attacker
    @state["field"][1][3] = target

    result = plan

    assert_not_empty result.actions
    assert_equal "attack", result.actions.first["type"]

    assert_equal(
      [1, 1],
      result.actions.first.dig("payload", "attacker")
    )

    assert_equal(
      [1, 3],
      result.actions.first.dig("payload", "target")
    )
  end

  test "makes a safe solo attack when headquarters support is unavailable" do
    headquarters = @state["field"][2][0]
    headquarters["has_attacked"] = true

    attacker = technique(
      player_id: AI_PLAYER_ID,
      hp: 10,
      firepower: 4
    )

    attacker["movement_count"] = 0

    @state["field"][1][2] = attacker

    target = technique(
      player_id: OPPONENT_ID,
      hp: 8,
      firepower: 4
    )

    target["has_attacked"] = true
    target["has_counterattacked"] = true

    @state["field"][0][3] = target

    result = plan

    assert_not_empty result.actions
    assert_equal "attack", result.actions.first["type"]

    assert_equal(
      [1, 2],
      result.actions.first.dig("payload", "attacker")
    )

    assert_equal(
      [0, 3],
      result.actions.first.dig("payload", "target")
    )
  end

  test "does not sacrifice a technique to a tank destroyer that shoots first" do
    @state["field"][2][0]["has_attacked"] = true

    attacker = technique(
      player_id: AI_PLAYER_ID,
      hp: 2,
      firepower: 4
    )

    tank_destroyer = technique(
      player_id: OPPONENT_ID,
      hp: 10,
      firepower: 6
    )
    tank_destroyer["technique_type"] = "tank_destroyer"

    @state["field"][1][1] = attacker
    @state["field"][1][2] = tank_destroyer

    result = plan

    assert_not_empty result.actions
    assert_equal "end_turn", result.actions.first["type"]
  end

  test "does not continue searching after end turn" do
    @state["field"][2][0]["has_attacked"] = true

    result = plan

    end_turn_index = result.actions.index do |action|
      action["type"] == "end_turn"
    end

    assert_equal(
      result.actions.length - 1,
      end_turn_index
    ) if end_turn_index
  end

  test "preserves expected visible state after every planned action" do
    visible_state = visible_state_for_ai
    result = plan(visible_state)

    assert_equal result.actions.length, result.steps.length
    refute_empty result.steps

    current_state = visible_state

    result.steps.each_with_index do |step, index|
      assert_equal result.actions[index], step.action

      simulation =
        DecisionProviders::OpponentEngine::Planning::StateSimulator.call(
          visible_state: current_state,
          player_id: AI_PLAYER_ID,
          action: step.action,
          current_time: @current_time
        )

      assert simulation.success?
      assert_equal simulation.visible_state, step.expected_visible_state

      current_state = step.expected_visible_state
    end
  end

  test "does not mutate the original visible state" do
    visible_state = visible_state_for_ai
    original_state = visible_state.deep_dup

    plan(visible_state)

    assert_equal original_state, visible_state
  end

  test "respects configured search depth" do
    @state["field"][2][0]["has_attacked"] = true

    result = plan(
      depth: 2,
      width: 3
    )

    assert_operator result.actions.length, :<=, 2
  end

  test "returns an empty plan when it is not the AI player's turn" do
    @state["current_player_id"] = OPPONENT_ID

    result = plan

    assert_empty result.actions
    assert_equal 0, result.expanded_nodes
  end

  test "rejects invalid search parameters" do
    assert_raises(ArgumentError) do
      plan(depth: 0)
    end

    assert_raises(ArgumentError) do
      plan(width: 0)
    end
  end

  test "penalizes idle forward movement but not vertical or rear movement" do
    @state["field"][1][1] = technique(
      player_id: AI_PLAYER_ID,
      hp: 10,
      firepower: 4
    )

    visible_state = visible_state_for_ai

    planner =
      DecisionProviders::OpponentEngine::Planning::TacticalPlanner.new(
        visible_state: visible_state,
        player_id: AI_PLAYER_ID,
        current_time: @current_time,
        depth: 5,
        width: 10
      )

    forward_move = {
      "type" => "move",
      "payload" => {
        "from" => [1, 1],
        "to" => [1, 2]
      }
    }

    vertical_move = {
      "type" => "move",
      "payload" => {
        "from" => [1, 1],
        "to" => [0, 1]
      }
    }

    rear_move = {
      "type" => "move",
      "payload" => {
        "from" => [1, 1],
        "to" => [1, 0]
      }
    }

    forward_penalty = planner.send(
      :idle_advance_penalty,
      [forward_move],
      []
    )

    vertical_penalty = planner.send(
      :idle_advance_penalty,
      [vertical_move],
      []
    )

    rear_penalty = planner.send(
      :idle_advance_penalty,
      [rear_move],
      []
    )

    assert_operator forward_penalty, :>, 0
    assert_equal 0.0, vertical_penalty
    assert_equal 0.0, rear_penalty
  end

  test "does not penalize forward movement followed by an attack from the new position" do
    @state["field"][1][1] = technique(
      player_id: AI_PLAYER_ID,
      hp: 10,
      firepower: 4
    )

    visible_state = visible_state_for_ai

    moved_state = @state.deep_dup
    moved_state["field"][1][2] = moved_state["field"][1][1]
    moved_state["field"][1][1] = nil

    moved_visible_state = GameEngine::VisibleState.call(
      state: moved_state,
      player_id: AI_PLAYER_ID
    )

    move_action = {
      "type" => "move",
      "payload" => {
        "from" => [1, 1],
        "to" => [1, 2]
      }
    }

    attack_action = {
      "type" => "attack",
      "payload" => {
        "attacker" => [1, 2],
        "target" => [0, 3]
      }
    }

    step = DecisionProviders::OpponentEngine::Planning::TacticalPlanner::Step.new(
      action: move_action,
      expected_visible_state: moved_visible_state
    )

    planner =
      DecisionProviders::OpponentEngine::Planning::TacticalPlanner.new(
        visible_state: visible_state,
        player_id: AI_PLAYER_ID,
        current_time: @current_time,
        depth: 5,
        width: 10
      )

    penalty = planner.send(
      :idle_advance_penalty,
      [move_action, attack_action],
      [step]
    )

    assert_equal 0.0, penalty
  end

  test "does not treat an attack before forward movement as protection from idle advance" do
    @state["field"][1][1] = technique(
      player_id: AI_PLAYER_ID,
      hp: 10,
      firepower: 4
    )

    visible_state = visible_state_for_ai

    attack_action = {
      "type" => "attack",
      "payload" => {
        "attacker" => [1, 1],
        "target" => [0, 3]
      }
    }

    move_action = {
      "type" => "move",
      "payload" => {
        "from" => [1, 1],
        "to" => [1, 2]
      }
    }

    step = DecisionProviders::OpponentEngine::Planning::TacticalPlanner::Step.new(
      action: attack_action,
      expected_visible_state: visible_state
    )

    planner =
      DecisionProviders::OpponentEngine::Planning::TacticalPlanner.new(
        visible_state: visible_state,
        player_id: AI_PLAYER_ID,
        current_time: @current_time,
        depth: 5,
        width: 10
      )

    penalty = planner.send(
      :idle_advance_penalty,
      [attack_action, move_action],
      [step]
    )

    assert_operator penalty, :>, 0
  end

  test "moves technique to free a deployment position before playing new technique" do
    @state["field"][2][0]["has_attacked"] = true

    @state["field"][1][0] = technique(
      player_id: AI_PLAYER_ID,
      hp: 10,
      firepower: 4
    ).merge(
      "movement_count" => 1
    )

    @state["field"][1][1] = technique(
      player_id: AI_PLAYER_ID,
      hp: 10,
      firepower: 4
    )

    @state["field"][2][1] = technique(
      player_id: AI_PLAYER_ID,
      hp: 10,
      firepower: 4
    )

    ai_player = @state["players"][AI_PLAYER_ID.to_s]
    ai_player["resources"] = 10

    ai_player["hand"] = [
      {
        "card_id" => 99,
        "card_type" => "technique",
        "name" => "Reserve Test Tank",
        "nation_id" => 10,
        "price" => 1,
        "technique" => {
          "technique_type" => "medium_tank",
          "hp" => 10,
          "firepower" => 4,
          "fuel" => 2,
          "attack_range" => 1,
          "movement_count" => 1,
          "movement_type" => "diagonal"
        }
      }
    ]

    result = plan

    assert_operator result.actions.length, :>=, 2

    first_action = result.actions.first
    second_action = result.actions.second

    assert_equal "move", first_action["type"]

    from = first_action.dig("payload", "from")
    to = first_action.dig("payload", "to")

    deployment_positions = [
      [1, 0],
      [1, 1],
      [2, 1]
    ]

    assert_includes deployment_positions, from
    refute_equal from, to

    # Освобождение клетки не должно сопровождаться
    # одиночным продвижением машины к противнику.
    assert_equal from[1], to[1]

    simulated_state = result.steps.first.expected_visible_state

    assert_nil simulated_state.dig("field", from[0], from[1])

    assert_equal "play_card", second_action["type"]

    assert_equal(
      from,
      [
        second_action.dig("payload", "row"),
        second_action.dig("payload", "column")
      ]
    )
  end

  test "preserves deployment branches when move branches dominate the beam" do
    @state["field"][1][0] = technique(
      player_id: AI_PLAYER_ID,
      hp: 10,
      firepower: 4
    ).merge(
      "movement_count" => 1
    )

    @state["players"]["42"]["hand"] = [
      {
        "card_id" => 99,
        "card_type" => "technique"
      }
    ]

    visible_state = visible_state_for_ai

    planner =
      DecisionProviders::OpponentEngine::Planning::TacticalPlanner.new(
        visible_state: visible_state,
        player_id: AI_PLAYER_ID,
        current_time: @current_time,
        depth: 5,
        width: 10
      )

    node_class =
      DecisionProviders::OpponentEngine::Planning::TacticalPlanner::Node

    move_nodes = 12.times.map do |index|
      node_class.new(
        visible_state: visible_state,
        actions: [
          {
            "type" => "move",
            "payload" => {
              "from" => [0, index % 4],
              "to" => [0, (index + 1) % 5]
            }
          }
        ],
        steps: [],
        score: 100 - index,
        terminal: false
      )
    end

    card_node = node_class.new(
      visible_state: visible_state,
      actions: [
        {
          "type" => "play_card",
          "payload" => {
            "card_id" => 99
          }
        }
      ],
      steps: [],
      score: 1,
      terminal: false
    )

    deployment_node = node_class.new(
      visible_state: visible_state,
      actions: [
        {
          "type" => "move",
          "payload" => {
            "from" => [1, 0],
            "to" => [0, 0]
          }
        }
      ],
      steps: [],
      score: 0,
      terminal: false
    )

    ranked = planner.send(
      :rank,
      move_nodes + [card_node, deployment_node]
    )

    first_actions = ranked.first(10).map do |node|
      node.actions.first
    end

    assert first_actions.any? do |action|
      action["type"] == "play_card" &&
        action.dig("payload", "card_id") == 99
    end

    assert first_actions.any? do |action|
      action["type"] == "move" &&
        action.dig("payload", "from") == [1, 0] &&
        action.dig("payload", "to") == [0, 0]
    end
  end

  test "preserves movement branches from different techniques" do
    visible_state = visible_state_for_ai

    planner =
      DecisionProviders::OpponentEngine::Planning::TacticalPlanner.new(
        visible_state: visible_state,
        player_id: AI_PLAYER_ID,
        current_time: @current_time,
        depth: 5,
        width: 2
      )

    node_class =
      DecisionProviders::OpponentEngine::Planning::TacticalPlanner::Node

    first_tank_nodes = 5.times.map do |index|
      node_class.new(
        visible_state: visible_state,
        actions: [
          {
            "type" => "move",
            "payload" => {
              "from" => [0, 1],
              "to" => [index, 2]
            }
          }
        ],
        steps: [],
        score: 100 - index,
        terminal: false
      )
    end

    second_tank_node = node_class.new(
      visible_state: visible_state,
      actions: [
        {
          "type" => "move",
          "payload" => {
            "from" => [0, 2],
            "to" => [1, 2]
          }
        }
      ],
      steps: [],
      score: 50,
      terminal: false
    )

    ranked = planner.send(
      :rank,
      first_tank_nodes + [second_tank_node]
    )

    selected_origins = ranked.first(2).map do |node|
      node.actions.first.dig("payload", "from")
    end

    assert_includes selected_origins, [0, 1]
    assert_includes selected_origins, [0, 2]
  end

  test "preserves attack branches from different techniques" do
    visible_state = visible_state_for_ai

    planner =
      DecisionProviders::OpponentEngine::Planning::TacticalPlanner.new(
        visible_state: visible_state,
        player_id: AI_PLAYER_ID,
        current_time: @current_time,
        depth: 5,
        width: 2
      )

    node_class =
      DecisionProviders::OpponentEngine::Planning::TacticalPlanner::Node

    first_tank_nodes = 5.times.map do |index|
      node_class.new(
        visible_state: visible_state,
        actions: [
          {
            "type" => "attack",
            "payload" => {
              "attacker" => [0, 1],
              "target" => [index, 3]
            }
          }
        ],
        steps: [],
        score: 100 - index,
        terminal: false
      )
    end

    second_tank_node = node_class.new(
      visible_state: visible_state,
      actions: [
        {
          "type" => "attack",
          "payload" => {
            "attacker" => [0, 2],
            "target" => [1, 3]
          }
        }
      ],
      steps: [],
      score: 50,
      terminal: false
    )

    ranked = planner.send(
      :rank,
      first_tank_nodes + [second_tank_node]
    )

    selected_attackers = ranked.first(2).map do |node|
      node.actions.first.dig("payload", "attacker")
    end

    assert_includes selected_attackers, [0, 1]
    assert_includes selected_attackers, [0, 2]
  end

  test "preserves different follow-up attacks within the same root branch" do
    visible_state = visible_state_for_ai

    planner =
      DecisionProviders::OpponentEngine::Planning::TacticalPlanner.new(
        visible_state: visible_state,
        player_id: AI_PLAYER_ID,
        current_time: @current_time,
        depth: 5,
        width: 4
      )

    node_class =
      DecisionProviders::OpponentEngine::Planning::TacticalPlanner::Node

    first_action = {
      "type" => "attack",
      "payload" => {
        "attacker" => [0, 4],
        "target" => [2, 0]
      }
    }

    first_tank_attack = {
      "type" => "attack",
      "payload" => {
        "attacker" => [0, 2],
        "target" => [1, 1]
      }
    }

    second_tank_attack = {
      "type" => "attack",
      "payload" => {
        "attacker" => [1, 2],
        "target" => [1, 1]
      }
    }

    third_tank_move = {
      "type" => "move",
      "payload" => {
        "from" => [2, 3],
        "to" => [2, 2]
      }
    }

    nodes = [
      node_class.new(
        visible_state: visible_state,
        actions: [first_action, first_tank_attack],
        steps: [],
        score: 100,
        terminal: false
      ),
      node_class.new(
        visible_state: visible_state,
        actions: [first_action, third_tank_move],
        steps: [],
        score: 90,
        terminal: false
      ),
      node_class.new(
        visible_state: visible_state,
        actions: [first_action, second_tank_attack],
        steps: [],
        score: 80,
        terminal: false
      )
    ]

    ranked = planner.send(:rank, nodes)

    assert_includes ranked, nodes[0]
    assert_includes ranked, nodes[1]
    assert_includes ranked, nodes[2]
  end

  test "preserves move and card branches when many attack targets dominate the beam" do
    visible_state = visible_state_for_ai

    planner =
      DecisionProviders::OpponentEngine::Planning::TacticalPlanner.new(
        visible_state: visible_state,
        player_id: AI_PLAYER_ID,
        current_time: @current_time,
        depth: 5,
        width: 10
      )

    node_class =
      DecisionProviders::OpponentEngine::Planning::TacticalPlanner::Node

    attack_nodes = 12.times.map do |index|
      node_class.new(
        visible_state: visible_state,
        actions: [
          {
            "type" => "attack",
            "payload" => {
              "attacker" => [1, 1],
              "target" => [index / 5, index % 5]
            }
          }
        ],
        steps: [],
        score: 100 - index,
        terminal: false
      )
    end

    move_node = node_class.new(
      visible_state: visible_state,
      actions: [
        {
          "type" => "move",
          "payload" => {
            "from" => [1, 1],
            "to" => [1, 2]
          }
        }
      ],
      steps: [],
      score: 1,
      terminal: false
    )

    card_node = node_class.new(
      visible_state: visible_state,
      actions: [
        {
          "type" => "play_card",
          "payload" => {
            "card_id" => 99
          }
        }
      ],
      steps: [],
      score: 0,
      terminal: false
    )

    ranked = planner.send(
      :rank,
      attack_nodes + [move_node, card_node]
    )

    first_actions = ranked.first(10).map do |node|
      node.actions.first
    end

    assert first_actions.any? { |action| action["type"] == "move" }
    assert first_actions.any? { |action| action["type"] == "play_card" }
  end

  test "rewards damage against a technique after its counterattack" do
    @state["field"][1][1] = technique(
      player_id: AI_PLAYER_ID,
      hp: 10,
      firepower: 4
    )

    target = technique(
      player_id: OPPONENT_ID,
      hp: 8,
      firepower: 4
    )

    target["has_counterattacked"] = true

    @state["field"][1][2] = target

    visible_state = visible_state_for_ai

    expected_state = visible_state.deep_dup
    expected_state["field"][1][2]["hp"] = 4

    action = {
      "type" => "attack",
      "payload" => {
        "attacker" => [1, 1],
        "target" => [1, 2]
      }
    }

    step =
      DecisionProviders::OpponentEngine::Planning::TacticalPlanner::Step.new(
        action: action,
        expected_visible_state: expected_state
      )

    planner =
      DecisionProviders::OpponentEngine::Planning::TacticalPlanner.new(
        visible_state: visible_state,
        player_id: AI_PLAYER_ID,
        current_time: @current_time,
        depth: 3,
        width: 5
      )

    bonus = planner.send(
      :counterattack_exploitation_bonus,
      [action],
      [step]
    )

    assert_equal 6.0, bonus

    # Если цель ещё может контратаковать, дополнительного бонуса нет.
    available_state = visible_state.deep_dup
    available_state["field"][1][2]["has_counterattacked"] = false

    planner =
      DecisionProviders::OpponentEngine::Planning::TacticalPlanner.new(
        visible_state: available_state,
        player_id: AI_PLAYER_ID,
        current_time: @current_time,
        depth: 3,
        width: 5
      )

    assert_equal(
      0.0,
      planner.send(
        :counterattack_exploitation_bonus,
        [action],
        [step]
      )
    )
  end

  private

  def plan(
    visible_state = nil,
    depth: DecisionProviders::OpponentEngine::Planning::TacticalPlanner::DEFAULT_DEPTH,
    width: DecisionProviders::OpponentEngine::Planning::TacticalPlanner::DEFAULT_WIDTH
  )
    visible_state ||= visible_state_for_ai

    DecisionProviders::OpponentEngine::Planning::TacticalPlanner.call(
      visible_state: visible_state,
      player_id: AI_PLAYER_ID,
      current_time: @current_time,
      depth: depth,
      width: width
    )
  end

  def visible_state_for_ai
    GameEngine::VisibleState.call(
      state: @state,
      player_id: AI_PLAYER_ID
    )
  end

  def add_headquarters_stats
    [@state["field"][2][0], @state["field"][0][4]].each do |headquarters|
      headquarters.merge!(
        "hp" => 20,
        "firepower" => 4,
        "fuel" => 5,
        "has_attacked" => false,
        "has_counterattacked" => false
      )
    end
  end

  def technique(player_id:, hp:, firepower:)
    {
      "type" => "technique",
      "card_id" => 15,
      "player_id" => player_id,
      "technique_type" => "medium_tank",
      "hp" => hp,
      "firepower" => firepower,
      "fuel" => 2,
      "attack_range" => 1,
      "movement_count" => 0,
      "movement_limit" => 1,
      "movement_type" => "diagonal",
      "has_attacked" => false,
      "has_counterattacked" => false
    }
  end
end
