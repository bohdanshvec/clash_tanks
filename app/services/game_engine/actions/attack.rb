module GameEngine
  module Actions
    class Attack
      def initialize(state, action)
        @state = state
        @action = action
      end

      def call
        return failure("Player does not exist") unless player_exists?
        return failure("It is not player's turn") unless current_player?

        attacker_position = @action.payload[:attacker]
        target_position = @action.payload[:target]

        return failure("Invalid coordinates") unless valid_coordinates?(attacker_position)
        return failure("Invalid coordinates") unless valid_coordinates?(target_position)

        attacker = object_at(attacker_position)
        target = object_at(target_position)

        return failure("Attacker cell is empty") unless attacker
        return failure("Target cell is empty") unless target
        return failure("Attacker does not belong to player") unless attacker["player_id"] == @action.player_id
        return failure("Target belongs to player") if target["player_id"] == @action.player_id

        case attacker["type"]
        when "technique"
          attack_technique(attacker, target, attacker_position, target_position)
        when "headquarters"
          attack_headquarters(attacker, target, attacker_position, target_position)
        else
          failure("Invalid attacker type")
        end
      end

      private

      # ------------------------------------------------------------------
      # Technique attacks
      # ------------------------------------------------------------------

      def attack_technique(attacker, target, attacker_position, target_position)
        return failure("Technique cannot attack headquarters at this range") if target["type"] == "headquarters" &&
          !valid_technique_to_headquarters_attack?(
            attacker,
            attacker_position,
            target_position
          )

        return failure("Target is not a technique") unless %w[technique headquarters].include?(target["type"])
        return failure("Technique has already attacked") if attacker["has_attacked"]

        if target["type"] == "technique"
          attack_technique_target(
            attacker,
            target,
            attacker_position,
            target_position
          )
        else
          attack_headquarters_target_from_technique(
            attacker,
            target,
            attacker_position,
            target_position
          )
        end
      end

      def attack_technique_target(attacker, target, attacker_position, target_position)
        return failure("Invalid attack range") unless valid_attack_range?(
          attacker,
          attacker_position,
          target_position
        )

        ptsau_first = ptsau_shoots_first?(
          attacker,
          target,
          attacker_position,
          target_position
        )

        new_state = @state.deep_dup

        new_attacker = object_at_in_state(
          new_state,
          attacker_position
        )

        new_target = object_at_in_state(
          new_state,
          target_position
        )

        new_attacker["has_attacked"] = true

        if ptsau_first
          new_attacker["hp"] -= new_target["firepower"]

          if new_attacker["hp"] <= 0
            move_to_graveyard(
              new_state,
              new_attacker
            )

            clear_field_cell(
              new_state,
              attacker_position
            )

            return Result.new(
              success: true,
              state: new_state,
              events: [{ type: "technique_destroyed" }]
            )
          end
        end

        new_target["hp"] -= new_attacker["firepower"]

        if new_target["hp"] <= 0
          move_to_graveyard(
            new_state,
            new_target
          )

          clear_field_cell(
            new_state,
            target_position
          )
        elsif !ptsau_first
          counterattack(
            new_state,
            attacker_position,
            target_position
          )
        end

        Result.new(
          success: true,
          state: new_state,
          events: [{ type: "technique_attacked" }]
        )
      end

      # Technique -> HQ
      #
      # Adjacent attack:
      # - normal combat;
      # - Technique shoots first;
      # - HQ may counterattack if it survives.
      #
      # Long-range attack:
      # - only SAU;
      # - friendly Technique must provide spotting near the enemy HQ;
      # - HQ does not counterattack.
      def attack_headquarters_target_from_technique(
        attacker,
        target,
        attacker_position,
        target_position
      )
        new_state = @state.deep_dup

        new_attacker = object_at_in_state(
          new_state,
          attacker_position
        )

        new_target = object_at_in_state(
          new_state,
          target_position
        )

				new_attacker["has_attacked"] = true

				apply_damage_to_headquarters(
					new_state,
					new_target,
					new_attacker["firepower"]
				)

        if new_target["hp"] > 0 && adjacent?(attacker_position, target_position)
          counterattack(
            new_state,
            attacker_position,
            target_position
          )
        end

        Result.new(
          success: true,
          state: new_state,
          events: [{ type: "headquarters_attacked" }]
        )
      end

      def valid_technique_to_headquarters_attack?(
        attacker,
        attacker_position,
        target_position
      )
        return true if adjacent?(attacker_position, target_position)

        attacker["technique_type"] == "artillery" &&
          allied_technique_near?(
            target_position,
            attacker["player_id"]
          )
      end

      # ------------------------------------------------------------------
      # Counterattack
      # ------------------------------------------------------------------

      def counterattack(state, attacker_position, target_position)
        attacker = object_at_in_state(
          state,
          attacker_position
        )

        defender = object_at_in_state(
          state,
          target_position
        )

        return unless attacker
        return unless defender
        return if defender["has_counterattacked"]

        return unless adjacent?(
          attacker_position,
          target_position
        )

				defender["has_counterattacked"] = true

				if attacker["type"] == "headquarters"
					apply_damage_to_headquarters(
						state,
						attacker,
						defender["firepower"]
					)
				else
					attacker["hp"] -= defender["firepower"]

					if attacker["hp"] <= 0
						move_to_graveyard(
							state,
							attacker
						)

						clear_field_cell(
							state,
							attacker_position
						)
					end
				end
      end

      # ------------------------------------------------------------------
      # Headquarters attacks
      # ------------------------------------------------------------------

      def attack_headquarters(
        attacker,
        target,
        attacker_position,
        target_position
      )
        return failure("Headquarters has already attacked") if attacker["has_attacked"]

        case target["type"]
        when "headquarters"
          attack_headquarters_target(
            attacker,
            target,
            attacker_position,
            target_position
          )
        when "technique"
          attack_technique_target_from_headquarters(
            attacker,
            target,
            attacker_position,
            target_position
          )
        else
          failure("Invalid target type")
        end
      end

      # HQ -> HQ
      #
      # Headquarters may attack the enemy Headquarters at any distance.
      # The defending HQ never counterattacks.
			def attack_headquarters_target(
				attacker,
				target,
				attacker_position,
				target_position
			)
				new_state = @state.deep_dup

				new_attacker = object_at_in_state(
					new_state,
					attacker_position
				)

				new_target = object_at_in_state(
					new_state,
					target_position
				)

				new_attacker["has_attacked"] = true

				total_firepower = headquarters_firepower_with_platoons(
					new_state,
					new_attacker
				)

				damage_platoons_after_headquarters_attack(
					new_state,
					new_attacker
				)

				apply_damage_to_headquarters(
					new_state,
					new_target,
					total_firepower
				)

				Result.new(
					success: true,
					state: new_state,
					events: [{ type: "headquarters_attacked" }]
				)
			end
      # HQ -> Technique
      #
      # This works like SAU:
      #
      # Adjacent:
      #   normal attack, Technique may counterattack.
      #
      # Long-range:
      #   friendly Technique or HQ must be adjacent to the target;
      #   no counterattack.
      def attack_technique_target_from_headquarters(
        attacker,
        target,
        attacker_position,
        target_position
      )
        return failure("Technique is out of headquarters attack range") unless
          valid_headquarters_to_technique_attack?(
            attacker,
            attacker_position,
            target_position
          )

        new_state = @state.deep_dup

        new_attacker = object_at_in_state(
          new_state,
          attacker_position
        )

        new_target = object_at_in_state(
          new_state,
          target_position
        )

				new_attacker["has_attacked"] = true

				total_firepower = headquarters_firepower_with_platoons(
					new_state,
					new_attacker
				)

				damage_platoons_after_headquarters_attack(
					new_state,
					new_attacker
				)

				apply_damage_to_headquarters(
					new_state,
					new_target,
					total_firepower
				)

				if new_target["hp"] <= 0
					move_to_graveyard(
						new_state,
						new_target
					)

					clear_field_cell(
						new_state,
						target_position
					)
				elsif adjacent?(attacker_position, target_position)
					counterattack(
						new_state,
						attacker_position,
						target_position
					)
				end
        Result.new(
          success: true,
          state: new_state,
          events: [{ type: "headquarters_attacked" }]
        )
      end

      def valid_headquarters_to_technique_attack?(
        attacker,
        attacker_position,
        target_position
      )
        return true if adjacent?(
          attacker_position,
          target_position
        )

        allied_unit_near?(
          target_position,
          attacker["player_id"]
        )
      end

      # ------------------------------------------------------------------
      # PT-SAU
      # ------------------------------------------------------------------

      def ptsau_shoots_first?(
        attacker,
        target,
        attacker_position,
        target_position
      )
        return false unless target["technique_type"] == "tank_destroyer"

        return false unless %w[
          light_tank
          medium_tank
          heavy_tank
        ].include?(attacker["technique_type"])

        adjacent?(
          attacker_position,
          target_position
        )
      end

      # ------------------------------------------------------------------
      # Position / spotting
      # ------------------------------------------------------------------

      def adjacent?(first_position, second_position)
        row_delta = (
          first_position[0] - second_position[0]
        ).abs

        column_delta = (
          first_position[1] - second_position[1]
        ).abs

        [row_delta, column_delta].max == 1
      end

      def allied_technique_near?(position, player_id)
        neighbor_objects(position).any? do |object|
          object &&
            object["type"] == "technique" &&
            object["player_id"].to_s == player_id.to_s
        end
      end

      def allied_unit_near?(position, player_id)
        neighbor_objects(position).any? do |object|
          object &&
            %w[technique headquarters].include?(object["type"]) &&
            object["player_id"].to_s == player_id.to_s
        end
      end

      def neighbor_objects(position)
        row = position[0]
        column = position[1]

        (-1..1).filter_map do |row_offset|
          (-1..1).filter_map do |column_offset|
            next if row_offset.zero? && column_offset.zero?

            neighbor_row = row + row_offset
            neighbor_column = column + column_offset

            next unless GameState.valid_coordinates?(
              row: neighbor_row,
              column: neighbor_column
            )

            @state["field"][neighbor_row][neighbor_column]
          end
        end.flatten
      end

      # ------------------------------------------------------------------
      # Graveyard
      # ------------------------------------------------------------------

      def move_to_graveyard(state, object)
        player = state["players"][object["player_id"].to_s]

        player["graveyard"] << object.deep_dup
      end

      def clear_field_cell(state, position)
        state["field"][position[0]][position[1]] = nil
      end

      # ------------------------------------------------------------------
      # State helpers
      # ------------------------------------------------------------------

      def player_exists?
        @state["players"].key?(
          @action.player_id.to_s
        )
      end

      def current_player?
        @state["current_player_id"].to_s ==
          @action.player_id.to_s
      end

      def valid_coordinates?(coordinates)
        coordinates.is_a?(Array) &&
          coordinates.length == 2 &&
          coordinates.all? { |coordinate| coordinate.is_a?(Integer) } &&
          GameState.valid_coordinates?(
            row: coordinates[0],
            column: coordinates[1]
          )
      end

      def object_at(coordinates)
        @state["field"][coordinates[0]][coordinates[1]]
      end

      def object_at_in_state(state, coordinates)
        state["field"][coordinates[0]][coordinates[1]]
      end

      def valid_attack_range?(attacker, from, to)
        row_delta = (to[0] - from[0]).abs
        column_delta = (to[1] - from[1]).abs

        distance = [row_delta, column_delta].max

        distance <= attacker["attack_range"]
      end

      def failure(error)
        Result.new(
          success: false,
          error: error
        )
      end
						
			def headquarters_firepower_with_platoons(state, headquarters)
				player = state["players"][headquarters["player_id"].to_s]
				platoons = player["platoons"] || []

				headquarters["firepower"] +
					platoons.compact.sum { |platoon| platoon["firepower"] }
			end

			def damage_platoons_after_headquarters_attack(state, headquarters)
				player = state["players"][headquarters["player_id"].to_s]
				platoons = player["platoons"] || []

				platoons.compact.each do |platoon|
					platoon["hp"] -= platoon["firepower"]

					next unless platoon["hp"] <= 0

					player["graveyard"] << platoon.deep_dup

					index = player["platoons"].index(platoon)
					player["platoons"][index] = nil
				end
			end
				
			def apply_damage_to_headquarters(state, headquarters, damage)
				return if damage <= 0

				player = state["players"][headquarters["player_id"].to_s]
				platoons = player["platoons"] || []

				remaining_damage = damage

				platoons.each do |platoon|
					next unless platoon

					absorbed_damage = [remaining_damage, platoon["armor"]].min

					platoon["hp"] -= absorbed_damage
					platoon["hp"] = 0 if platoon["hp"] < 0
					remaining_damage -= absorbed_damage

					if platoon["hp"] <= 0
						player["graveyard"] << platoon.deep_dup

						index = player["platoons"].index(platoon)
						player["platoons"][index] = nil
					end

					break if remaining_damage <= 0
				end

				headquarters["hp"] -= remaining_damage
				headquarters["hp"] = 0 if headquarters["hp"] < 0
			end
    end
  end
end
