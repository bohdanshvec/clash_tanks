module GameEngine
  class AvailableActions
    def self.call(state:, player_id:)
      new(state, player_id).call
    end

    def initialize(state, player_id)
      @state = state
      @player_id = player_id.to_s
      @player = @state["players"][@player_id]
    end

    def call
      return empty_result unless @player
      return empty_result unless current_player?

      {
        "field" => field_actions,
        "hand" => hand_actions
      }
    end

    private

    def empty_result
      {
        "field" => {},
        "hand" => {}
      }
    end

    def current_player?
      @state["current_player_id"].to_s == @player_id
    end

    # ------------------------------------------------------------------
    # Field
    # ------------------------------------------------------------------

    def field_actions
      actions = {}

      each_field_object do |object, position|
        next unless own_object?(object)

        case object["type"]
        when "technique"
          actions[position_key(position)] = {
            "moves" => available_moves(object, position),
            "attacks" => available_attacks(object, position)
          }
        when "headquarters"
          actions[position_key(position)] = {
            "moves" => [],
            "attacks" => available_attacks(object, position)
          }
        end
      end

      actions
    end

    def available_moves(technique, position)
      return [] if technique["movement_count"].to_i <= 0

      positions = []

      each_neighbor_position(position) do |target_position|
        next unless empty_field_position?(target_position)

        next unless GameEngine::Rules::TechniqueMovement.valid?(
          technique,
          position,
          target_position
        )

        positions << target_position
      end

      positions
    end

    def available_attacks(attacker, attacker_position)
      return [] if attacker["has_attacked"]

      attacks = []

      each_field_object do |target, target_position|
        next unless target
        next if own_object?(target)

        next unless valid_attack_target?(
          attacker,
          target,
          attacker_position,
          target_position
        )

        attacks << target_position
      end

      attacks
    end

    def valid_attack_target?(
      attacker,
      target,
      attacker_position,
      target_position
    )
      case attacker["type"]
      when "technique"
        valid_technique_attack?(
          attacker,
          target,
          attacker_position,
          target_position
        )
      when "headquarters"
        valid_headquarters_attack?(
          target,
          attacker_position,
          target_position
        )
      else
        false
      end
    end

    def valid_technique_attack?(
      attacker,
      target,
      attacker_position,
      target_position
    )
      case target["type"]
      when "technique"
        return true if GameEngine::Rules::AttackRange.valid?(
          attacker,
          attacker_position,
          target_position
        )

        attacker["technique_type"] == "artillery" &&
          GameEngine::Rules::Spotting.allied_unit_near?(
            @state,
            target_position,
            attacker["player_id"]
          )
      when "headquarters"
        return true if GameEngine::Rules::Position.adjacent?(
          attacker_position,
          target_position
        )

        attacker["technique_type"] == "artillery" &&
          GameEngine::Rules::Spotting.allied_technique_near?(
            @state,
            target_position,
            attacker["player_id"]
          )
      else
        false
      end
    end

    def valid_headquarters_attack?(
      target,
      attacker_position,
      target_position
    )
      case target["type"]
      when "headquarters"
        true
      when "technique"
        return true if GameEngine::Rules::Position.adjacent?(
          attacker_position,
          target_position
        )

        GameEngine::Rules::Spotting.allied_technique_near?(
          @state,
          target_position,
          @player_id
        )
      else
        false
      end
    end

    # ------------------------------------------------------------------
    # Hand
    # ------------------------------------------------------------------

    def hand_actions
      actions = {}

      @player["hand"].each do |card|
        actions[card["card_id"].to_s] = available_card_action(card)
      end

      actions
    end

    def available_card_action(card)
      case card["card_type"]
      when "technique"
        available_technique_card_action(card)
      when "platoon"
        available_platoon_card_action(card)
      when "order"
        available_order_card_action(card)
      else
        {}
      end
    end

		def available_technique_card_action(card)
			return {
				"type" => "technique",
				"drop_zone" => "field",
				"resources_sufficient" => false,
				"positions" => []
			} unless enough_resources?(card)

			{
				"type" => "technique",
				"drop_zone" => "field",
				"resources_sufficient" => true,
				"positions" => available_technique_positions
			}
		end

    def available_technique_positions
      positions = []

      each_field_position do |position|
        next unless empty_field_position?(position)

        next unless adjacent_to_own_headquarters?(position)

        positions << position
      end

      positions
    end

		def available_platoon_card_action(card)
			return {
				"type" => "platoon",
				"drop_zone" => "platoon_bar",
				"resources_sufficient" => false,
				"slots" => []
			} unless enough_resources?(card)

			{
				"type" => "platoon",
				"drop_zone" => "platoon_bar",
				"resources_sufficient" => true,
				"slots" => available_platoon_slots
			}
		end

    def available_platoon_slots
      @player["platoons"].each_with_index.filter_map do |platoon, index|
        index if platoon.nil?
      end
    end

		def available_order_card_action(card)
			return {
				"type" => "order",
				"targets" => [],
				"resources_sufficient" => false
			} unless enough_resources?(card)

			abilities = card["abilities"] || []

			return {
				"type" => "order",
				"drop_zone" => "field",
				"resources_sufficient" => true
			} if abilities.none? { |ability| targeted_ability?(ability) }

			{
				"type" => "order",
				"targets" => available_order_targets(card),
				"resources_sufficient" => true
			}
		end

		def available_order_targets(card)
			targets = []

			return targets unless card["abilities"]

			return targets unless card["abilities"].any? do |ability|
				targeted_ability?(ability)
			end

			each_field_object do |object, position|
				next unless object
				next unless object["type"] == "technique"
				next unless enemy_object?(object)

				targets << position
			end

			targets
		end

    def targeted_ability?(ability)
      ability["code"] == "damage_technique"
    end

    # ------------------------------------------------------------------
    # Field helpers
    # ------------------------------------------------------------------

    def each_field_object
      each_field_position do |position|
        yield(
          object_at(position),
          position
        )
      end
    end

    def each_field_position
      GameState::FIELD_HEIGHT.times do |row|
        GameState::FIELD_WIDTH.times do |column|
          yield [row, column]
        end
      end
    end

    def each_neighbor_position(position)
      row = position[0]
      column = position[1]

      (-1..1).each do |row_offset|
        (-1..1).each do |column_offset|
          next if row_offset.zero? && column_offset.zero?

          target_position = [
            row + row_offset,
            column + column_offset
          ]

          next unless GameState.valid_coordinates?(
            row: target_position[0],
            column: target_position[1]
          )

          yield target_position
        end
      end
    end

    def object_at(position)
      @state["field"][position[0]][position[1]]
    end

    def empty_field_position?(position)
      object_at(position).nil?
    end

		def own_object?(object)
			object && object["player_id"].to_s == @player_id
		end

    def enemy_object?(object)
      !own_object?(object)
    end

    def adjacent_to_own_headquarters?(position)
      each_field_position do |field_position|
        object = object_at(field_position)

        next unless object
        next unless object["type"] == "headquarters"
        next unless own_object?(object)

        return true if GameEngine::Rules::Position.adjacent?(
          field_position,
          position
        )
      end

      false
    end

    # ------------------------------------------------------------------
    # Cards / resources
    # ------------------------------------------------------------------

    def enough_resources?(card)
      @player["resources"].to_i >= card["price"].to_i
    end

    def position_key(position)
      position.join(",")
    end
  end
end
