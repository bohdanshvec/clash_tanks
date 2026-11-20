
require "test_helper"

class DecisionProviders::OpponentEngine::Planning::StrategicEvaluatorTest <
  ActiveSupport::TestCase

  setup do
    @ai_player_id = "42"
    @opponent_id = "57"

    @state = GameEngine::GameState.initial(
      current_player_id: 42,
      participants: [
        headquarters_participant(
          player_id: 42,
          nation_id: 10
        ),
        headquarters_participant(
          player_id: 57,
          nation_id: 20
        )
      ]
    )
  end

  test "values tank destroyers above equivalent medium tanks" do
    medium_tank = test_technique(57)
    tank_destroyer = test_technique(57)

    tank_destroyer["technique_type"] = "tank_destroyer"

    assert_operator(
      technique_value(tank_destroyer),
      :>,
      technique_value(medium_tank)
    )
  end

  test "values artillery above equivalent medium tanks" do
    medium_tank = test_technique(57)
    artillery = test_technique(57)

    artillery["technique_type"] = "artillery"

    assert_operator(
      technique_value(artillery),
      :>,
      technique_value(medium_tank)
    )
  end

  test "values techniques that contribute fuel to future turns" do
    without_fuel = test_technique(57)
    with_fuel = test_technique(57)

    without_fuel["fuel"] = 0
    with_fuel["fuel"] = 2

    assert_operator(
      technique_value(with_fuel),
      :>,
      technique_value(without_fuel)
    )
  end

  test "returns a numeric and repeatable score" do
    visible_state = visible_state_for_ai
    original_state = visible_state.deep_dup

    first_score = evaluate(visible_state)
    second_score = evaluate(visible_state)

    assert_kind_of Numeric, first_score
    assert_equal first_score, second_score
    assert_equal original_state, visible_state
  end

  test "score breakdown sums to the strategic evaluation" do
    visible_state = visible_state_for_ai

    evaluator =
      DecisionProviders::OpponentEngine::Planning::StrategicEvaluator.new(
        visible_state: visible_state,
        player_id: @ai_player_id
      )

    breakdown = evaluator.score_breakdown

    assert_kind_of Hash, breakdown
    assert_equal evaluate(visible_state), breakdown.values.sum

    assert_includes breakdown.keys, :enemy_threat
    assert_includes breakdown.keys, :offensive_group
    assert_includes breakdown.keys, :formation_penalty
  end

  test "profiles strategic evaluation components without changing scores" do
    visible_state = visible_state_for_ai
    profile = {}

    score =
      DecisionProviders::OpponentEngine::Planning::StrategicEvaluator.call(
        visible_state: visible_state,
        player_id: @ai_player_id,
        profile: profile
      )

    breakdown =
      DecisionProviders::OpponentEngine::Planning::StrategicEvaluator.new(
        visible_state: visible_state,
        player_id: @ai_player_id,
        profile: profile,
        profile_scope: :breakdown
      ).score_breakdown

    assert_equal score, breakdown.values.sum

    assert_operator(
      profile.fetch(:"evaluate.headquarters")[:calls],
      :>,
      0
    )

    assert_operator(
      profile.fetch(:"evaluate.enemy_threat")[:calls],
      :>,
      0
    )

    assert_operator(
      profile.fetch(:"breakdown.combined_attack_opportunity")[:calls],
      :>,
      0
    )

    assert_operator(
      profile.fetch(:"breakdown.enemy_threat")[:total_ms],
      :>=,
      0
    )
  end

  test "values own headquarters health" do
    visible_state = visible_state_for_ai
    damaged_state = visible_state.deep_dup

    damaged_state["field"][2][0]["hp"] = 10

    assert_operator(
      evaluate(visible_state),
      :>,
      evaluate(damaged_state)
    )
  end

  test "values damage dealt to enemy headquarters" do
    visible_state = visible_state_for_ai
    damaged_state = visible_state.deep_dup

    damaged_state["field"][0][4]["hp"] = 10

    assert_operator(
      evaluate(damaged_state),
      :>,
      evaluate(visible_state)
    )
  end

  test "values own techniques and platoons" do
    baseline_score = evaluate(visible_state_for_ai)

    @state["field"][1][1] = {
      "type" => "technique",
      "card_id" => 15,
      "player_id" => 42,
      "technique_type" => "medium_tank",
      "hp" => 10,
      "firepower" => 4,
      "fuel" => 2,
      "attack_range" => 1,
      "movement_count" => 1,
      "has_attacked" => false
    }

    @state["players"]["42"]["platoons"][0] = {
      "type" => "platoon",
      "card_id" => 16,
      "player_id" => 42,
      "hp" => 8,
      "firepower" => 3,
      "armor" => 2,
      "fuel" => 1
    }

    assert_operator(
      evaluate(visible_state_for_ai),
      :>,
      baseline_score
    )
  end

  test "values techniques positioned closer to enemy headquarters" do
    far_state = @state.deep_dup
    near_state = @state.deep_dup

    far_state["field"][1][1] = test_technique(42)
    near_state["field"][0][3] = test_technique(42)

    assert_operator(
      evaluate(state: near_state),
      :>,
      evaluate(state: far_state)
    )
  end

  test "rewards each step of individual technique advancement" do
    far_state = @state.deep_dup
    near_state = @state.deep_dup

    far_state["field"][1][1] = test_technique(42)
    near_state["field"][1][2] = test_technique(42)

    assert_equal(
      1.0,
      positional_score(state: near_state) -
        positional_score(state: far_state)
    )
  end

  test "values the same offensive support formation for both headquarters" do
    first_player_state = @state.deep_dup

    first_player_state["field"][0][3] = test_technique(57)
    first_player_state["field"][1][2] = test_technique(42)
    first_player_state["field"][2][1] = test_technique(42)

    second_player_state = @state.deep_dup

    second_player_state["field"][2][1] = test_technique(42)
    second_player_state["field"][1][2] = test_technique(57)
    second_player_state["field"][0][3] = test_technique(57)

    first_score = offensive_group_score(
      state: first_player_state,
      player_id: "42"
    )

    second_score = offensive_group_score(
      state: second_player_state,
      player_id: "57"
    )

    assert_operator first_score, :>, 0
    assert_equal first_score, second_score
  end

  test "rewards a rear tank that moves into support range of the vanguard" do
    distant_state = @state.deep_dup

    distant_state["field"][0][3] = test_technique(57)
    distant_state["field"][0][2] = test_technique(42)
    distant_state["field"][2][1] = test_technique(42)
    distant_state["field"][2][1]["movement_count"] = 0

    supporting_state = distant_state.deep_dup

    supporting_state["field"][1][1] =
      supporting_state["field"][2][1]
    supporting_state["field"][2][1] = nil

    assert_operator(
      offensive_group_score(state: supporting_state),
      :>,
      offensive_group_score(state: distant_state)
    )
  end

  test "prefers an advancing healthy supporter to a retreating one" do
    advancing_state = @state.deep_dup

    advancing_state["field"][0][3] = test_technique(57)
    advancing_state["field"][0][2] = test_technique(42)
    advancing_state["field"][1][1] = test_technique(42)
    advancing_state["field"][1][1]["movement_count"] = 0

    retreating_state = advancing_state.deep_dup

    retreating_state["field"][2][1] =
      retreating_state["field"][1][1]
    retreating_state["field"][1][1] = nil

    assert_operator(
      offensive_group_score(state: advancing_state),
      :>,
      offensive_group_score(state: retreating_state)
    )
  end

  test "preserves proportional offensive group value for damaged tanks" do
    healthy_state = @state.deep_dup

    healthy_state["field"][0][3] = test_technique(57)
    healthy_state["field"][0][2] = test_technique(42)
    healthy_state["field"][1][1] = test_technique(42)
    healthy_state["field"][1][1]["movement_count"] = 0

    full_score = offensive_group_score(state: healthy_state)

    three_hp_state = healthy_state.deep_dup
    three_hp_state["field"][1][1]["hp"] = 3

    three_hp_score = offensive_group_score(state: three_hp_state)

    one_hp_state = healthy_state.deep_dup
    one_hp_state["field"][1][1]["hp"] = 1

    one_hp_score = offensive_group_score(state: one_hp_state)

    destroyed_state = healthy_state.deep_dup
    destroyed_state["field"][1][1]["hp"] = 0

    destroyed_score = offensive_group_score(state: destroyed_state)

    assert_operator full_score, :>, three_hp_score
    assert_operator three_hp_score, :>, one_hp_score
    assert_operator one_hp_score, :>, 0
    assert_equal 0, destroyed_score
  end

  test "does not reward a cluster without a reachable offensive objective" do
    state = @state.deep_dup

    state["field"][1][1] = test_technique(42)
    state["field"][2][1] = test_technique(42)

    assert_equal 0, offensive_group_score(state: state)
  end

  test "keeps a decisive solo attack more valuable than formation readiness" do
    state = @state.deep_dup

    target = test_technique(57)
    target["hp"] = 10
    target["firepower"] = 0

    leader = test_technique(42)
    leader["firepower"] = 20

    state["field"][0][3] = target
    state["field"][0][2] = leader
    state["field"][1][1] = test_technique(42)
    state["field"][1][1]["movement_count"] = 0

    visible_state = GameEngine::VisibleState.call(
      state: state,
      player_id: @ai_player_id
    )

    simulation =
      DecisionProviders::OpponentEngine::Planning::StateSimulator.call(
        visible_state: visible_state,
        player_id: @ai_player_id,
        action: {
          "type" => "attack",
          "payload" => {
            "attacker" => [0, 2],
            "target" => [0, 3]
          }
        },
        current_time: Time.current
      )

    assert simulation.success?
    assert_nil simulation.visible_state.dig("field", 0, 3)
    assert_operator evaluate(simulation.visible_state), :>, evaluate(visible_state)
  end

  test "penalizes enemy techniques positioned near own headquarters" do
    safe_state = @state.deep_dup
    threatened_state = @state.deep_dup

    safe_state["field"][0][3] = test_technique(57)
    threatened_state["field"][2][1] = test_technique(57)

    assert_operator(
      evaluate(state: safe_state),
      :>,
      evaluate(state: threatened_state)
    )
  end

  test "does not reward merely having unused actions" do
    @state["field"][1][1] = test_technique(42)
    @state["field"][1][2] = test_technique(57)

    with_actions = visible_state_for_ai

    without_actions = with_actions.deep_dup
    without_actions["available_actions"] = {
      "field" => {},
      "hand" => {}
    }

    assert_equal(
      evaluate(with_actions),
      evaluate(without_actions)
    )
  end

  test "returns a dominant score for a finished game" do
    visible_state = visible_state_for_ai

    visible_state["status"] = "finished"
    visible_state["result"] = {
      "winner_id" => 42,
      "loser_id" => 57,
      "reason" => "headquarters_destroyed"
    }

    assert_equal(
      DecisionProviders::OpponentEngine::Planning::StrategicEvaluator::WIN_SCORE,
      evaluate(visible_state)
    )
  end

  test "returns a dominant negative score after defeat" do
    visible_state = visible_state_for_ai

    visible_state["status"] = "finished"
    visible_state["result"] = {
      "winner_id" => 57,
      "loser_id" => 42,
      "reason" => "headquarters_destroyed"
    }

    assert_equal(
      -DecisionProviders::OpponentEngine::Planning::StrategicEvaluator::WIN_SCORE,
      evaluate(visible_state)
    )
  end

  test "values opening a deployment position through movement" do
    blocked_state = @state.deep_dup

    [
      [1, 0],
      [1, 1],
      [2, 1]
    ].each do |position|
      blocked_state["field"][position[0]][position[1]] =
        test_technique(42)
    end

    reserve_state = blocked_state.deep_dup

    reserve_state["field"][0][0] =
      reserve_state["field"][1][0]

    reserve_state["field"][1][0] = nil

    assert_operator(
      evaluate(state: reserve_state),
      :>,
      evaluate(state: blocked_state)
    )
  end

  test "does not reward moving a technique into reserve without opening a deployment position" do
    forward_state = @state.deep_dup

    forward_state["field"][0][1] = test_technique(42)
    forward_state["field"][1][3] = test_technique(42)

    reserve_state = forward_state.deep_dup

    reserve_state["field"][0][0] =
      reserve_state["field"][0][1]

    reserve_state["field"][0][1] = nil

    assert_operator(
      evaluate(state: forward_state),
      :>,
      evaluate(state: reserve_state)
    )
  end

  test "values reserve movement for the second player" do
    second_state = GameEngine::GameState.initial(
      current_player_id: 57,
      participants: [
        headquarters_participant(
          player_id: 42,
          nation_id: 10
        ),
        headquarters_participant(
          player_id: 57,
          nation_id: 20
        )
      ]
    )

    second_state["field"][1][4] = test_technique(57)

    reserve_state = second_state.deep_dup

    reserve_state["field"][2][4] =
      reserve_state["field"][1][4]

    reserve_state["field"][1][4] = nil

    assert_operator(
      evaluate(state: reserve_state, player_id: "57"),
      :>,
      evaluate(state: second_state, player_id: "57")
    )
  end

  test "values multiple techniques that can attack the same target" do
    grouped_state = @state.deep_dup

    grouped_state["field"][0][2] = test_technique(42)
    grouped_state["field"][2][2] = test_technique(42)
    grouped_state["field"][1][3] = test_technique(57)

    unsupported_state = grouped_state.deep_dup

    unsupported_state["field"][2][2]["has_attacked"] = true

    assert_operator(
      evaluate(state: grouped_state),
      :>,
      evaluate(state: unsupported_state)
    )
  end

  test "values a coordinated attack by two techniques that can move into attack positions" do
    state = @state.deep_dup

    state["field"][0][3] = test_technique(57)
    state["field"][2][2] = test_technique(42)
    state["field"][2][4] = test_technique(42)

    assert_operator(
      combined_attack_opportunity_score(state: state),
      :>,
      0
    )
  end

  test "does not reward proximity alone when no attack target exists" do
    close_state = @state.deep_dup
    scattered_state = @state.deep_dup

    close_positions = [
      [1, 2],
      [1, 3]
    ]

    scattered_positions = [
      [2, 3],
      [0, 2]
    ]

    [close_state, scattered_state].each do |state|
      positions = state.equal?(close_state) ?
        close_positions :
        scattered_positions

      positions.each do |position|
        technique = test_technique(42)
        technique["movement_count"] = 0
        technique["has_attacked"] = true

        state["field"][position[0]][position[1]] = technique
      end
    end

    assert_equal(
      positional_score(state: close_state),
      positional_score(state: scattered_state)
    )
  end

  test "values a coordinated attack by two techniques and headquarters" do
    state = @state.deep_dup

    state["field"][0][3] = test_technique(57)
    state["field"][0][3]["hp"] = 12

    state["field"][0][2] = test_technique(42)
    state["field"][1][2] = test_technique(42)

    state["field"][2][0]["firepower"] = 4
    state["field"][2][0]["has_attacked"] = false

    assert_operator(
      combined_attack_opportunity_score(state: state),
      :>,
      0
    )
  end

  test "values nonlethal coordinated damage by two techniques and headquarters" do
    state = @state.deep_dup

    state["field"][0][3] = test_technique(57)
    state["field"][0][3]["hp"] = 30

    state["field"][0][2] = test_technique(42)
    state["field"][1][2] = test_technique(42)

    state["field"][2][0]["firepower"] = 4
    state["field"][2][0]["has_attacked"] = false

    assert_operator(
      combined_attack_opportunity_score(state: state),
      :>,
      0
    )
  end

  test "values a coordinated attack by two techniques after headquarters has attacked" do
    state = @state.deep_dup

    state["field"][0][3] = test_technique(57)
    state["field"][0][3]["hp"] = 8

    state["field"][0][2] = test_technique(42)
    state["field"][1][2] = test_technique(42)

    state["field"][2][0]["firepower"] = 4
    state["field"][2][0]["has_attacked"] = true

    assert_operator(
      combined_attack_opportunity_score(state: state),
      :>,
      0
    )
  end

  test "values nonlethal coordinated damage by one technique and headquarters" do
    state = @state.deep_dup

    state["field"][0][3] = test_technique(57)
    state["field"][0][3]["hp"] = 8
    state["field"][0][3]["has_counterattacked"] = true

    state["field"][0][2] = test_technique(42)

    state["field"][2][0]["firepower"] = 3

    assert_operator(
      combined_attack_opportunity_score(state: state),
      :>,
      0
    )
  end

  test "values a lethal coordinated attack by one technique and headquarters" do
    state = @state.deep_dup

    state["field"][0][3] = test_technique(57)
    state["field"][0][3]["hp"] = 7

    state["field"][0][2] = test_technique(42)

    state["field"][2][0]["firepower"] = 3

    assert_operator(
      combined_attack_opportunity_score(state: state),
      :>,
      0
    )
  end

  test "values moving a technique to enable a headquarters attack" do
    state = @state.deep_dup

    state["field"][0][3] = test_technique(57)
    state["field"][1][1] = test_technique(42)

    state["field"][0][3]["hp"] = 3

    assert_operator(
      headquarters_attack_opportunity_score(state: state),
      :>,
      0
    )
  end

  test "does not value a nonlethal headquarters attack after spotting move" do
    state = @state.deep_dup

    state["field"][0][3] = test_technique(57)
    state["field"][0][3]["hp"] = 4

    state["field"][1][1] = test_technique(42)

    assert_equal(
      0,
      headquarters_attack_opportunity_score(state: state)
    )
  end

  test "does not value a headquarters attack when no spotting move is available" do
    state = @state.deep_dup

    state["field"][0][3] = test_technique(57)

    technique = test_technique(42)
    technique["movement_count"] = 0

    state["field"][1][1] = technique

    assert_equal(
      0,
      headquarters_attack_opportunity_score(state: state)
    )
  end

  test "detects an enemy technique threatening an own technique" do
    state = @state.deep_dup

    own_technique = test_technique(42)
    own_technique["firepower"] = 2

    enemy_technique = test_technique(57)
    enemy_technique["firepower"] = 6

    state["field"][1][2] = own_technique
    state["field"][1][3] = enemy_technique

    assert_operator(
      threat_score(state: state),
      :>,
      0
    )
  end

  test "considers enemy attacks available on its next turn" do
    state = @state.deep_dup

    own_technique = test_technique(42)
    own_technique["firepower"] = 2

    enemy_technique = test_technique(57)
    enemy_technique["firepower"] = 6

    state["field"][1][2] = own_technique
    state["field"][1][3] = enemy_technique
    state["field"][1][3]["has_attacked"] = true

    assert_operator(
      threat_score(state: state),
      :>,
      0
    )
  end

  test "detects an enemy technique that can move before attacking" do
    state = @state.deep_dup

    own_technique = test_technique(42)
    own_technique["firepower"] = 2

    enemy_technique = test_technique(57)
    enemy_technique["firepower"] = 6

    state["field"][2][2] = own_technique
    state["field"][0][2] = enemy_technique

    assert_operator(
      threat_score(state: state),
      :>,
      0
    )
  end

  test "detects artillery attacks using allied spotting" do
    state = @state.deep_dup

    artillery = test_technique(57)
    artillery["technique_type"] = "artillery"
    artillery["movement_limit"] = 0
    artillery["movement_count"] = 0

    state["field"][0][0] = artillery
    state["field"][2][1] = test_technique(57)

    assert_operator(
      threat_score(state: state),
      :>,
      0
    )
  end

  test "accounts for an available counterattack when estimating enemy threat" do
    available_state = @state.deep_dup

    own_technique = test_technique(42)
    own_technique["firepower"] = 2

    enemy_technique = test_technique(57)
    enemy_technique["firepower"] = 6

    available_state["field"][1][2] = own_technique
    available_state["field"][1][3] = enemy_technique

    spent_state = available_state.deep_dup
    spent_state["field"][1][2]["has_counterattacked"] = true

    assert_operator(
      threat_score(state: spent_state),
      :>,
      threat_score(state: available_state)
    )
  end

  test "accounts for a tank destroyer shooting first" do
    state = @state.deep_dup

    tank_destroyer = test_technique(42)
    tank_destroyer["technique_type"] = "tank_destroyer"
    tank_destroyer["firepower"] = 10

    enemy_technique = test_technique(57)
    enemy_technique["firepower"] = 4

    state["field"][1][2] = tank_destroyer
    state["field"][1][3] = enemy_technique

    assert_equal(
      0,
      threat_score(state: state)
    )

    state["field"][1][2]["has_counterattacked"] = true

    assert_operator(
      threat_score(state: state),
      :>,
      0
    )
  end

  test "values waiting when next turn enables a coordinated attack" do
    state = @state.deep_dup

    state["field"][0][3] = test_technique(57)
    state["field"][0][3]["hp"] = 8
    state["field"][0][3]["movement_limit"] = 0
    state["field"][0][3]["movement_count"] = 0

    state["field"][2][2] = test_technique(42)
    state["field"][2][4] = test_technique(42)

    [
      [2, 2],
      [2, 4]
    ].each do |position|
      technique = state["field"][position[0]][position[1]]

      technique["movement_count"] = 0
      technique["has_attacked"] = true
    end

    assert_operator(
      future_coordination_opportunity_score(
        state: state,
        current_player_id: 57
      ),
      :>,
      0
    )
  end

  test "reduces waiting value when enemy can threaten the attacking group" do
    state = @state.deep_dup

    state["field"][0][3] = test_technique(57)
    state["field"][0][3]["hp"] = 8
    state["field"][0][3]["movement_limit"] = 0
    state["field"][0][3]["movement_count"] = 0

    state["field"][2][2] = test_technique(42)
    state["field"][2][4] = test_technique(42)

    [
      [2, 2],
      [2, 4]
    ].each do |position|
      technique = state["field"][position[0]][position[1]]
      technique["movement_count"] = 0
      technique["has_attacked"] = true
    end

    safe_score = future_coordination_opportunity_score(
      state: state,
      current_player_id: 57
    )

    threatened_state = state.deep_dup

    enemy = test_technique(57)
    enemy["hp"] = 100
    enemy["firepower"] = 8
    enemy["movement_limit"] = 0
    enemy["movement_count"] = 0

    threatened_state["field"][1][3] = enemy

    threatened_score = future_coordination_opportunity_score(
      state: threatened_state,
      current_player_id: 57
    )

    assert_operator safe_score, :>, 0
    assert_operator threatened_score, :<, safe_score
  end

  test "does not reward waiting when only one technique can attack" do
    state = @state.deep_dup

    state["field"][0][3] = test_technique(57)
    state["field"][2][2] = test_technique(42)

    state["field"][2][2]["movement_count"] = 0
    state["field"][2][2]["movement_limit"] = 0
    state["field"][2][2]["has_attacked"] = true

    assert_equal(
      0,
      future_coordination_opportunity_score(
        state: state,
        current_player_id: 57
      )
    )
  end

  test "does not add future waiting bonus during own turn" do
    state = @state.deep_dup

    state["field"][0][3] = test_technique(57)
    state["field"][2][2] = test_technique(42)
    state["field"][2][4] = test_technique(42)

    assert_equal(
      0,
      future_coordination_opportunity_score(
        state: state,
        current_player_id: 42
      )
    )
  end

  test "does not reward waiting when the current attack opportunity is already as strong" do
    state = @state.deep_dup

    state["field"][0][3] = test_technique(57)
    state["field"][0][3]["hp"] = 20

    state["field"][2][2] = test_technique(42)
    state["field"][2][4] = test_technique(42)

    assert_equal(
      0,
      future_coordination_opportunity_score(
        state: state,
        current_player_id: 57
      )
    )
  end

  test "does not reward a coordinated attack when counterattacks destroy the attacking tanks" do
    state = @state.deep_dup

    target = test_technique(57)
    target["hp"] = 30
    target["firepower"] = 100

    state["field"][0][3] = target
    state["field"][0][2] = test_technique(42)
    state["field"][1][2] = test_technique(42)

    assert_equal(
      0,
      combined_attack_opportunity_score(state: state)
    )
  end

  test "values a vertical offensive line for the first player" do
    formed_state = @state.deep_dup

    formed_state["field"][0][1] = test_technique(42)
    formed_state["field"][1][1] = test_technique(42)

    scattered_state = @state.deep_dup

    scattered_state["field"][0][1] = test_technique(42)
    scattered_state["field"][1][2] = test_technique(42)

    assert_operator(
      offensive_lane_score(state: formed_state),
      :>,
      offensive_lane_score(state: scattered_state)
    )
  end

  test "values a formation group on the same lane without adjacent rows" do
    formed_state = @state.deep_dup

    formed_state["field"][0][1] = test_technique(42)
    formed_state["field"][2][1] = test_technique(42)

    scattered_state = @state.deep_dup

    scattered_state["field"][0][1] = test_technique(42)
    scattered_state["field"][2][2] = test_technique(42)

    assert_operator(
      offensive_lane_score(state: formed_state),
      :>,
      offensive_lane_score(state: scattered_state)
    )
  end

  test "values three techniques on the formation lane above two" do
    two_tanks_state = @state.deep_dup

    two_tanks_state["field"][0][1] = test_technique(42)
    two_tanks_state["field"][1][1] = test_technique(42)

    three_tanks_state = two_tanks_state.deep_dup

    three_tanks_state["field"][2][1] = test_technique(42)

    assert_operator(
      offensive_lane_score(state: three_tanks_state),
      :>,
      offensive_lane_score(state: two_tanks_state)
    )
  end

  test "values a vertical offensive line for the second player" do
    second_state = GameEngine::GameState.initial(
      current_player_id: 57,
      participants: [
        headquarters_participant(
          player_id: 42,
          nation_id: 10
        ),
        headquarters_participant(
          player_id: 57,
          nation_id: 20
        )
      ]
    )

    formed_state = second_state.deep_dup

    formed_state["field"][1][3] = test_technique(57)
    formed_state["field"][2][3] = test_technique(57)

    scattered_state = second_state.deep_dup

    scattered_state["field"][1][3] = test_technique(57)
    scattered_state["field"][2][2] = test_technique(57)

    assert_operator(
      offensive_lane_score(
        state: formed_state,
        player_id: "57"
      ),
      :>,
      offensive_lane_score(
        state: scattered_state,
        player_id: "57"
      )
    )
  end

  test "does not value a single technique as an offensive line" do
    state = @state.deep_dup

    state["field"][1][1] = test_technique(42)

    assert_equal(
      0,
      offensive_lane_score(state: state)
    )
  end

  test "does not reward additional free deployment positions" do
    one_free_position = @state.deep_dup
    two_free_positions = @state.deep_dup

    [
      [1, 0],
      [2, 1]
    ].each do |position|
      one_free_position["field"][position[0]][position[1]] =
        test_technique(42)
    end

    two_free_positions["field"][1][0] =
      test_technique(42)

    assert_equal(
      deployment_capacity_score(state: one_free_position),
      deployment_capacity_score(state: two_free_positions)
    )
  end

  private

  def technique_value(technique)
    visible_state = visible_state_for_ai

    evaluator =
      DecisionProviders::OpponentEngine::Planning::StrategicEvaluator.new(
        visible_state: visible_state,
        player_id: @ai_player_id
      )

    evaluator.send(:technique_value, technique)
  end

  def offensive_lane_score(state:, player_id: @ai_player_id)
    visible_state = GameEngine::VisibleState.call(
      state: state,
      player_id: player_id
    )

    evaluator =
      DecisionProviders::OpponentEngine::Planning::StrategicEvaluator.new(
        visible_state: visible_state,
        player_id: player_id
      )

    evaluator.send(:offensive_lane_score)
  end

  def deployment_capacity_score(state:)
    visible_state = GameEngine::VisibleState.call(
      state: state,
      player_id: @ai_player_id
    )

    evaluator =
      DecisionProviders::OpponentEngine::Planning::StrategicEvaluator.new(
        visible_state: visible_state,
        player_id: @ai_player_id
      )

    evaluator.send(:deployment_capacity_score)
  end

  def future_coordination_opportunity_score(
    state:,
    current_player_id:
  )
    visible_state = GameEngine::VisibleState.call(
      state: state,
      player_id: @ai_player_id
    )

    visible_state["current_player_id"] = current_player_id.to_s

    visible_state["available_actions"] = {
      "field" => {},
      "hand" => {}
    }

    evaluator =
      DecisionProviders::OpponentEngine::Planning::StrategicEvaluator.new(
        visible_state: visible_state,
        player_id: @ai_player_id
      )

    evaluator.send(:future_coordination_opportunity_score)
  end

  def combined_attack_opportunity_score(state:)
    visible_state = GameEngine::VisibleState.call(
      state: state,
      player_id: @ai_player_id
    )

    evaluator =
      DecisionProviders::OpponentEngine::Planning::StrategicEvaluator.new(
        visible_state: visible_state,
        player_id: @ai_player_id
      )

    evaluator.send(:combined_attack_opportunity_score)
  end

  def offensive_group_score(state:, player_id: @ai_player_id)
    visible_state = GameEngine::VisibleState.call(
      state: state,
      player_id: player_id
    )

    evaluator =
      DecisionProviders::OpponentEngine::Planning::StrategicEvaluator.new(
        visible_state: visible_state,
        player_id: player_id
      )

    evaluator.send(:offensive_group_score)
  end

  def positional_score(state:)
    visible_state = GameEngine::VisibleState.call(
      state: state,
      player_id: @ai_player_id
    )

    evaluator =
      DecisionProviders::OpponentEngine::Planning::StrategicEvaluator.new(
        visible_state: visible_state,
        player_id: @ai_player_id
      )

    evaluator.send(:positional_score)
  end

  def headquarters_attack_opportunity_score(state:)
    visible_state = GameEngine::VisibleState.call(
      state: state,
      player_id: @ai_player_id
    )

    evaluator =
      DecisionProviders::OpponentEngine::Planning::StrategicEvaluator.new(
        visible_state: visible_state,
        player_id: @ai_player_id
      )

    evaluator.send(:headquarters_attack_opportunity_score)
  end

  def visible_state_for_ai
    GameEngine::VisibleState.call(
      state: @state,
      player_id: @ai_player_id
    )
  end

  def evaluate(visible_state = nil, state: nil, player_id: @ai_player_id)
    visible_state ||= GameEngine::VisibleState.call(
      state: state || @state,
      player_id: player_id
    )

    DecisionProviders::OpponentEngine::Planning::StrategicEvaluator.call(
      visible_state: visible_state,
      player_id: player_id
    )
  end

  def threat_score(state:)
    visible_state = GameEngine::VisibleState.call(
      state: state,
      player_id: @ai_player_id
    )

    evaluator =
      DecisionProviders::OpponentEngine::Planning::StrategicEvaluator.new(
        visible_state: visible_state,
        player_id: @ai_player_id
      )

    evaluator.send(:enemy_threat_score)
  end

  def test_technique(player_id)
    {
      "type" => "technique",
      "card_id" => 15,
      "player_id" => player_id,
      "technique_type" => "medium_tank",
      "hp" => 10,
      "firepower" => 4,
      "fuel" => 2,
      "attack_range" => 1,
      "movement_count" => 1,
      "movement_limit" => 1,
      "movement_type" => "diagonal",
      "has_attacked" => false,
      "has_counterattacked" => false
    }
  end
end
