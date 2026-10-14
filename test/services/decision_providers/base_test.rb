require "test_helper"

class DecisionProvidersBaseTest < ActiveSupport::TestCase
  test "base provider requires call implementation" do
    provider = DecisionProviders::Base.new(
      context: build_context
    )

    error = assert_raises(NotImplementedError) do
      provider.call
    end

    assert_includes error.message, "must implement #call"
  end

  test "subclass can access context and return an action" do
    context = build_context

    provider_class = Class.new(DecisionProviders::Base) do
      def call
        GameEngine::Action.new(
          player_id: context.player_id,
          type: "end_turn"
        )
      end
    end

    action = provider_class.new(context: context).call

    assert_instance_of GameEngine::Action, action
    assert_equal "1", action.player_id
    assert_equal "end_turn", action.type
  end

  private

  def build_context
    DecisionProviders::Context.new(
      state: {
        "status" => "started",
        "turn_number" => 1,
        "current_player_id" => "1",
        "field" => Array.new(3) { Array.new(5) },
        "result" => nil,
        "players" => {
          "1" => build_player,
          "2" => build_player
        }
      },
      player_id: "1"
    )
  end

  def build_player
    {
      "nation_id" => 1,
      "hand" => [],
      "deck" => [],
      "platoons" => [nil, nil, nil],
      "resources" => 0,
      "remaining_time" => 600,
      "empty_deck_draw_attempts" => 0,
      "graveyard" => []
    }
  end
end
