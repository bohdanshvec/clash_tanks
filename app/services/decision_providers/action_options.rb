# app/services/decision_providers/action_options.rb

module DecisionProviders
  class ActionOptions
    def self.call(visible_state)
      new(visible_state).call
    end

    def initialize(visible_state)
      @state = visible_state
      @available_actions = visible_state.fetch("available_actions", {})
      @players = visible_state.fetch("players", {})
      @player_id = visible_state["current_player_id"].to_s
      @player = @players[@player_id]
    end

    def call
      return [] unless @player
      return [] unless @state["status"] == "started"

      actions = []

      add_field_actions(actions)
      add_card_actions(actions)

      # Завершение хода всегда доступно активному игроку.
      actions << {
        "type" => "end_turn",
        "payload" => {}
      }

      actions
    end

    private

    def add_field_actions(actions)
      field_actions = @available_actions.fetch("field", {})

      field_actions.each do |position_key, available|
        from = parse_position(position_key)

        next unless from

        available.fetch("moves", []).each do |to|
          actions << {
            "type" => "move",
            "payload" => {
              "from" => from,
              "to" => to
            }
          }
        end

        available.fetch("attacks", []).each do |target|
          actions << {
            "type" => "attack",
            "payload" => {
              "attacker" => from,
              "target" => target
            }
          }
        end
      end
    end

    def add_card_actions(actions)
      available_cards = @available_actions.fetch("hand", {})
      hand = @player.fetch("hand", [])

      hand.each do |card|
        card_id = card["card_id"].to_s
        available = available_cards[card_id]

        next unless available
        next unless available["resources_sufficient"]

        case card["card_type"]
        when "technique"
          add_technique_actions(actions, card, available)
        when "platoon"
          add_platoon_action(actions, card, available)
        when "order"
          add_order_actions(actions, card, available)
        end
      end
    end

    def add_technique_actions(actions, card, available)
      available.fetch("positions", []).each do |position|
        next unless valid_position?(position)

        actions << {
          "type" => "play_card",
          "payload" => {
            "card_id" => card["card_id"],
            "row" => position[0],
            "column" => position[1]
          }
        }
      end
    end

    def add_platoon_action(actions, card, available)
      # PlayCard самостоятельно выбирает первый свободный слот.
      # Поэтому передавать номер слота в payload не требуется.
      return if available.fetch("slots", []).empty?

      actions << {
        "type" => "play_card",
        "payload" => {
          "card_id" => card["card_id"]
        }
      }
    end

    def add_order_actions(actions, card, available)
      abilities = card.fetch("abilities", [])

      targeted = abilities.any? do |ability|
        ability["code"] == "damage_technique"
      end

      if targeted
        available.fetch("targets", []).each do |target|
          next unless valid_position?(target)

          actions << {
            "type" => "play_card",
            "payload" => {
              "card_id" => card["card_id"],
              "targets" => [target]
            }
          }
        end
      else
        actions << {
          "type" => "play_card",
          "payload" => {
            "card_id" => card["card_id"],
            "targets" => []
          }
        }
      end
    end

    def parse_position(value)
      parts = value.split(",")
      return unless parts.length == 2

      position = parts.map do |part|
        Integer(part, 10)
      rescue ArgumentError
        return
      end

      return unless valid_position?(position)

      position
    end

    def valid_position?(position)
      position.is_a?(Array) &&
        position.length == 2 &&
        position.all? { |coordinate| coordinate.is_a?(Integer) } &&
        coordinate_in_bounds?(position[0], position[1])
    end

    def coordinate_in_bounds?(row, column)
      row.between?(0, 2) && column.between?(0, 4)
    end
  end
end
