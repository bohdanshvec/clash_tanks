require "test_helper"

class DecisionProvidersContextTest < ActiveSupport::TestCase
  test "exposes visible state without opponent hand" do
    state = build_state

    context = DecisionProviders::Context.new(
      state: state,
      player_id: "1"
    )

    players = context.visible_state.fetch("players")

    assert_equal "1", context.player_id

    assert players.fetch("1").key?("hand")
    assert players.fetch("2").key?("hand_count")
    assert_not players.fetch("2").key?("hand")

    assert_equal 1, players.fetch("2").fetch("hand_count")
  end

  test "exposes available actions from visible state" do
    context = DecisionProviders::Context.new(
      state: build_state,
      player_id: "1"
    )

    assert_equal(
      context.visible_state.fetch("available_actions"),
      context.available_actions
    )
  end

  test "does not allow modification of context data" do
    context = DecisionProviders::Context.new(
      state: build_state,
      player_id: "1"
    )

    assert_raises(FrozenError) do
      context.visible_state["status"] = "finished"
    end

    assert_raises(FrozenError) do
      context.available_actions["field"]["test"] = []
    end
  end

  private

  def build_state
    {
      "status" => "started",
      "turn_number" => 1,
      "current_player_id" => "1",
      "turn_started_at" => Time.current.iso8601,
      "field" => Array.new(3) { Array.new(5) },
      "result" => nil,
      "players" => {
        "1" => build_player(
          hand: [
            {
              "card_id" => "card-1",
              "card_type" => "technique",
              "price" => 1
            }
          ]
        ),
        "2" => build_player(
          hand: [
            {
              "card_id" => "secret-card",
              "card_type" => "technique",
              "price" => 1
            }
          ]
        )
      }
    }
  end

  def build_player(hand:)
    {
      "nation_id" => 1,
      "hand" => hand,
      "deck" => [],
      "platoons" => [nil, nil, nil],
      "resources" => 0,
      "remaining_time" => 600,
      "empty_deck_draw_attempts" => 0,
      "graveyard" => []
    }
  end
end
