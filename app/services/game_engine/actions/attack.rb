module GameEngine
  module Actions
    class Attack < Base

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
        return failure("Attacker does not belong to player") unless own_object?(attacker)
        return failure("Target belongs to player") if own_object?(target)

        case attacker["type"]
        when "technique"
          attack_technique(
            attacker,
            target,
            attacker_position,
            target_position
          )
        when "headquarters"
          attack_headquarters(
            attacker,
            target,
            attacker_position,
            target_position
          )
        else
          failure("Invalid attacker type")
        end
      end

      private

      # ------------------------------------------------------------------
      # Technique attacks
      # ------------------------------------------------------------------

      def attack_technique(
        attacker,
        target,
        attacker_position,
        target_position
      )
        return failure("Technique has already attacked") if attacker["has_attacked"]

        case target["type"]
        when "technique"
          attack_technique_target(
            attacker,
            target,
            attacker_position,
            target_position
          )
        when "headquarters"
          attack_headquarters_target_from_technique(
            attacker,
            target,
            attacker_position,
            target_position
          )
        else
          failure("Invalid target type")
        end
      end

			def attack_technique_target(attacker, target, attacker_position, target_position)
				return failure("Invalid attack range") unless valid_technique_to_technique_attack?(
					attacker,
					attacker_position,
					target_position
				)

				new_state = @state.deep_dup
				new_attacker = object_at_in_state(new_state, attacker_position)
				new_target = object_at_in_state(new_state, target_position)
				new_attacker["has_attacked"] = true

				if ptsau_shoots_first?(new_attacker, new_target, attacker_position, target_position)
					return attack_with_ptsau_first(
						new_state,
						new_attacker,
						new_target,
						attacker_position,
						target_position
					)
				end

				perform_shot(new_state, new_attacker, new_target, target_position)

				if new_target["hp"] > 0 && adjacent?(attacker_position, target_position)
					counterattack(new_state, attacker_position, target_position)
				end

				Result.new(success: true, state: new_state, events: [{ type: "technique_attacked" }])
			end

			def valid_technique_to_technique_attack?(attacker, attacker_position, target_position)
				return true if valid_attack_range?(attacker, attacker_position, target_position)

				attacker["technique_type"] == "artillery" &&
					allied_unit_near?(target_position, attacker["player_id"])
			end

      # PT-SAU special combat:
      # - defending PT-SAU shoots first;
      # - if attacking Technique survives, it shoots;
      # - no counterattack after this exchange.
      def attack_with_ptsau_first(
        state,
        attacker,
        target,
        attacker_position,
        target_position
      )
        perform_shot(
          state,
          target,
          attacker,
          attacker_position
        )

        return Result.new(
          success: true,
          state: state,
          events: [{ type: "technique_destroyed" }]
        ) if attacker["hp"] <= 0

        perform_shot(
          state,
          attacker,
          target,
          target_position
        )

        Result.new(
          success: true,
          state: state,
          events: [{ type: "technique_attacked" }]
        )
      end

      # Technique -> HQ
      #
      # Adjacent:
      # - normal combat;
      # - Technique shoots first;
      # - HQ may counterattack if it survives.
      #
      # Long-range:
      # - only SAU;
      # - friendly Technique must provide spotting near the enemy HQ;
      # - HQ does not counterattack.
			def attack_headquarters_target_from_technique(
				attacker,
				target,
				attacker_position,
				target_position
			)
				return failure("Technique cannot attack headquarters at this range") unless
					valid_technique_to_headquarters_attack?(
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

				perform_shot(
					new_state,
					new_attacker,
					new_target,
					target_position
				)

				if new_target["hp"] <= 0
					return finish_game_after_headquarters_destruction(
						new_state,
						new_attacker,
						new_target,
						"headquarters_attacked"
					)
				end

				if adjacent?(attacker_position, target_position)
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

				perform_shot(
					new_state,
					new_attacker,
					new_target,
					target_position
				)

				if new_target["hp"] <= 0
					return finish_game_after_headquarters_destruction(
						new_state,
						new_attacker,
						new_target,
						"headquarters_attacked"
					)
				end

				Result.new(
					success: true,
					state: new_state,
					events: [{ type: "headquarters_attacked" }]
				)
			end

      # HQ -> Technique
      #
      # Adjacent:
      # - normal attack;
      # - Technique may counterattack.
      #
      # Long-range:
      # - friendly Technique or HQ must be adjacent to target;
      # - no counterattack.
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

        perform_shot(
          new_state,
          new_attacker,
          new_target,
          target_position
        )

        if new_target["hp"] > 0 &&
            adjacent?(attacker_position, target_position)
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

			def valid_headquarters_to_technique_attack?(attacker, attacker_position, target_position)
				return true if adjacent?(attacker_position, target_position)

				allied_technique_near?(target_position, attacker["player_id"])
			end

      # ------------------------------------------------------------------
      # Common shot / counterattack
      # ------------------------------------------------------------------

      # Common shot mechanism used by:
      # - normal attack;
      # - counterattack;
      # - HQ attack;
      # - Technique attack;
      # - second shot in PT-SAU combat.
      #
      # This method never starts a counterattack.
      def perform_shot(
        state,
        attacker,
        target,
        target_position
      )
        damage = firepower_for_shot(
          state,
          attacker
        )

        apply_shot_damage(
          state,
          target,
          damage,
          target_position
        )
      end

      def firepower_for_shot(state, attacker)
        if attacker["type"] == "headquarters"
          fire_with_headquarters(
            state,
            attacker
          )
        else
          attacker["firepower"]
        end
      end

      def apply_shot_damage(
        state,
        target,
        damage,
        target_position
      )
        if target["type"] == "headquarters"
          apply_damage_to_headquarters(
            state,
            target,
            damage
          )
        else
          target["hp"] -= damage
          target["hp"] = 0 if target["hp"] < 0

          if target["hp"] <= 0
            destroy_technique(
              state,
              target,
              target_position
            )
          end
        end
      end

      def counterattack(
        state,
        attacker_position,
        target_position
      )
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

        perform_shot(
          state,
          defender,
          attacker,
          attacker_position
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
      # Headquarters + Platoons
      # ------------------------------------------------------------------

      def fire_with_headquarters(
        state,
        headquarters
      )
        total_firepower = headquarters_total_firepower(
          state,
          headquarters
        )

        damage_platoons_after_headquarters_attack(
          state,
          headquarters
        )

        total_firepower
      end

      def headquarters_total_firepower(
        state,
        headquarters
      )
        player = state["players"][headquarters["player_id"].to_s]
        platoons = player["platoons"] || []

        headquarters["firepower"] +
          platoons.compact.sum { |platoon| platoon["firepower"] }
      end

      def damage_platoons_after_headquarters_attack(
        state,
        headquarters
      )
        player = state["players"][headquarters["player_id"].to_s]
        platoons = player["platoons"] || []

        platoons.each_with_index do |platoon, index|
          next unless platoon

          platoon["hp"] -= platoon["firepower"]
          platoon["hp"] = 0 if platoon["hp"] < 0

          next unless platoon["hp"] <= 0

          player["graveyard"] << platoon.deep_dup
          player["platoons"][index] = nil
        end
      end

      # Incoming damage to HQ is absorbed by Platoons in slot order.
      #
      # Slot 0 -> Slot 1 -> Slot 2 -> Slot 3
      #
      # Each Platoon can absorb up to its armor value.
      # Remaining damage continues to the next Platoon and then to HQ.
			def apply_damage_to_headquarters(state, headquarters, damage)
				return if damage <= 0

				player = state["players"][headquarters["player_id"].to_s]
				platoons = player["platoons"] || []
				remaining_damage = damage

				platoons.each_with_index do |platoon, index|
					next unless platoon

					armor = platoon["armor"].to_i
					absorbed_damage = [remaining_damage, armor].min

					platoon["hp"] -= absorbed_damage
					platoon["hp"] = 0 if platoon["hp"] < 0
					remaining_damage -= absorbed_damage

					next unless platoon["hp"] <= 0

					player["graveyard"] << platoon.deep_dup
					player["platoons"][index] = nil

					break if remaining_damage <= 0
				end

				headquarters["hp"] -= remaining_damage
				headquarters["hp"] = 0 if headquarters["hp"] < 0
			end

      # ------------------------------------------------------------------
      # Destruction / graveyard
      # ------------------------------------------------------------------

			def finish_game_after_headquarters_destruction(
				state,
				attacker,
				destroyed_headquarters,
				attack_event_type
			)
				finish_result = GameEngine::FinishGame.call(
					state: state,
					winner_id: attacker["player_id"],
					loser_id: destroyed_headquarters["player_id"],
					reason: "headquarters_destroyed"
				)

				return finish_result unless finish_result.success?

				Result.new(
					success: true,
					state: finish_result.state,
					events: [
						{ type: attack_event_type },
						*finish_result.events
					]
				)
			end

      def destroy_technique(
        state,
        technique,
        position
      )
        move_to_graveyard(
          state,
          technique
        )

        clear_field_cell(
          state,
          position
        )
      end

      def move_to_graveyard(
        state,
        object
      )
        player = state["players"][object["player_id"].to_s]

        player["graveyard"] << object.deep_dup
      end

      def clear_field_cell(
        state,
        position
      )
        state["field"][position[0]][position[1]] = nil
      end

      # ------------------------------------------------------------------
      # Position / spotting
      # ------------------------------------------------------------------

      def adjacent?(
        first_position,
        second_position
      )
        row_delta = (
          first_position[0] - second_position[0]
        ).abs

        column_delta = (
          first_position[1] - second_position[1]
        ).abs

        [row_delta, column_delta].max == 1
      end

      def allied_technique_near?(
        position,
        player_id
      )
        neighbor_objects(position).any? do |object|
          object &&
            object["type"] == "technique" &&
            object["player_id"].to_s == player_id.to_s
        end
      end

      def allied_unit_near?(
        position,
        player_id
      )
        neighbor_objects(position).any? do |object|
          object &&
            %w[technique headquarters].include?(object["type"]) &&
            object["player_id"].to_s == player_id.to_s
        end
      end

      def neighbor_objects(position)
        row = position[0]
        column = position[1]

        (-1..1).flat_map do |row_offset|
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
        end
      end

      # ------------------------------------------------------------------
      # State helpers
      # ------------------------------------------------------------------

      def own_object?(object)
        object["player_id"].to_s ==
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

      def object_at_in_state(
        state,
        coordinates
      )
        state["field"][coordinates[0]][coordinates[1]]
      end

      def valid_attack_range?(
        attacker,
        from,
        to
      )
        row_delta = (to[0] - from[0]).abs
        column_delta = (to[1] - from[1]).abs

        distance = [row_delta, column_delta].max

        distance <= attacker["attack_range"]
      end
    end
  end
end
