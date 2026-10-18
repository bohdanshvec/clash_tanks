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

        unless %w[technique headquarters].include?(attacker["type"])
          return failure("Invalid attacker type")
        end

        unless %w[technique headquarters].include?(target["type"])
          return failure("Invalid target type")
        end

        if attacker["has_attacked"]
          error = if attacker["type"] == "headquarters"
            "Headquarters has already attacked"
          else
            "Technique has already attacked"
          end

          return failure(error)
        end

        unless valid_attack?(
          attacker,
          target,
          attacker_position,
          target_position
        )
          return failure(attack_range_error(attacker, target))
        end

        execute_attack(
          attacker_position,
          target_position
        )
      end

      private

      # ------------------------------------------------------------------
      # Attack validation
      # ------------------------------------------------------------------

      def valid_attack?(
        attacker,
        target,
        attacker_position,
        target_position
      )
        # Headquarters may attack enemy headquarters at any distance.
        return true if headquarters_vs_headquarters?(attacker, target)

        adjacent = GameEngine::Rules::Position.adjacent?(
          attacker_position,
          target_position
        )

        # Headquarters -> Technique
        if attacker["type"] == "headquarters"
          return true if adjacent

          return GameEngine::Rules::Spotting.allied_technique_near?(
            @state,
            target_position,
            attacker["player_id"]
          )
        end

        # Technique -> Headquarters
        if target["type"] == "headquarters"
          return true if adjacent

          return attacker["technique_type"] == "artillery" &&
            GameEngine::Rules::Spotting.allied_technique_near?(
              @state,
              target_position,
              attacker["player_id"]
            )
        end

        # Technique -> Technique
        return true if GameEngine::Rules::AttackRange.valid?(
          attacker,
          attacker_position,
          target_position
        )

        # Artillery may use allied spotting for a distant attack.
        attacker["technique_type"] == "artillery" &&
          GameEngine::Rules::Spotting.allied_unit_near?(
            @state,
            target_position,
            attacker["player_id"]
          )
      end

      def attack_range_error(attacker, target)
        if attacker["type"] == "headquarters"
          "Technique is out of headquarters attack range"
        elsif target["type"] == "headquarters"
          "Technique cannot attack headquarters at this range"
        else
          "Invalid attack range"
        end
      end

      # ------------------------------------------------------------------
      # Combat classification
      # ------------------------------------------------------------------

      def headquarters_vs_headquarters?(attacker, target)
        attacker["type"] == "headquarters" &&
          target["type"] == "headquarters"
      end

      def combat_type(
        attacker,
        target,
        attacker_position,
        target_position
      )
        # Headquarters vs Headquarters never causes a counterattack.
        return :ranged if headquarters_vs_headquarters?(attacker, target)

        adjacent = GameEngine::Rules::Position.adjacent?(
          attacker_position,
          target_position
        )

        # Any other non-adjacent attack is ranged.
        return :ranged unless adjacent

        # Defending PT-SAU may shoot first.
        return :ptsau_first if ptsau_shoots_first?(attacker, target)

        # All remaining adjacent attacks use normal combat.
        :normal
      end

      def ptsau_shoots_first?(attacker, target)
        return false unless target["type"] == "technique"
        return false unless target["technique_type"] == "tank_destroyer"

        # PT-SAU may counterattack only once per opponent turn.
        return false if target["has_counterattacked"]

        # PT-SAU vs PT-SAU:
        # the attacking PT-SAU shoots first.
        return false if attacker["technique_type"] == "tank_destroyer"

        true
      end

      # ------------------------------------------------------------------
      # Execute attack
      # ------------------------------------------------------------------

      def execute_attack(attacker_position, target_position)
        new_state = @state.deep_dup

        attacker = object_at_in_state(
          new_state,
          attacker_position
        )

        target = object_at_in_state(
          new_state,
          target_position
        )

        attacker["has_attacked"] = true

        scenario = combat_type(
          attacker,
          target,
          attacker_position,
          target_position
        )

        case scenario
        when :ranged
          execute_ranged_combat(
            new_state,
            attacker,
            target,
            target_position
          )
        when :normal
          execute_normal_combat(
            new_state,
            attacker,
            target,
            attacker_position,
            target_position
          )
        when :ptsau_first
          execute_ptsau_first_combat(
            new_state,
            attacker,
            target,
            attacker_position,
            target_position
          )
        end

        finish_attack(
          new_state,
          attacker,
          target,
          attacker_position,
          target_position,
          scenario
        )
      end

      # ------------------------------------------------------------------
      # Ranged combat
      # ------------------------------------------------------------------

      # Ranged attacks:
      # - Headquarters -> Headquarters;
      # - Headquarters -> Technique with spotting;
      # - Artillery -> Technique with spotting;
      # - Artillery -> Headquarters with spotting;
      # - other permitted non-adjacent Technique attacks.
      #
      # Ranged attacks never cause counterattacks.
      def execute_ranged_combat(
        state,
        attacker,
        target,
        target_position
      )
        perform_shot(
          state,
          attacker,
          target,
          target_position
        )
      end

      # ------------------------------------------------------------------
      # Normal adjacent combat
      # ------------------------------------------------------------------

      # The attacker shoots first.
      #
      # If the defender survives and has an unused counterattack,
      # the defender shoots back.
      def execute_normal_combat(
        state,
        attacker,
        target,
        attacker_position,
        target_position
      )
        perform_shot(
          state,
          attacker,
          target,
          target_position
        )

        # A destroyed defender cannot counterattack.
        return if target["hp"] <= 0

        counterattack(
          state,
          attacker_position,
          target_position
        )
      end

      # ------------------------------------------------------------------
      # PT-SAU adjacent combat
      # ------------------------------------------------------------------

      # A defending PT-SAU with an available counterattack
      # shoots before the attacker.
      #
      # Exception:
      # PT-SAU vs PT-SAU uses normal combat.
      #
      # If the attacker survives, it performs its attack.
      def execute_ptsau_first_combat(
        state,
        attacker,
        target,
        attacker_position,
        target_position
      )
        # The PT-SAU uses the common counterattack mechanism.
        # This also sets has_counterattacked = true.
        counterattack(
          state,
          attacker_position,
          target_position
        )

        # A destroyed attacker cannot shoot.
        return if attacker["hp"] <= 0

        perform_shot(
          state,
          attacker,
          target,
          target_position
        )
      end

      # ------------------------------------------------------------------
      # Attack result
      # ------------------------------------------------------------------

      def finish_attack(
        state,
        attacker,
        target,
        attacker_position,
        target_position,
        scenario
      )
        # The attacking Headquarters may be destroyed
        # by a normal or preemptive counterattack.
        if attacker["type"] == "headquarters" && attacker["hp"] <= 0
          return finish_game_after_headquarters_destruction(
            state,
            target,
            attacker,
            "headquarters_attacked",
            attacker_position,
            target_position
          )
        end

        # The defending Headquarters may be destroyed
        # by an ordinary attack.
        if target["type"] == "headquarters" && target["hp"] <= 0
          return finish_game_after_headquarters_destruction(
            state,
            attacker,
            target,
            "headquarters_attacked",
            attacker_position,
            target_position
          )
        end

        event_type = attack_event_type(
          attacker,
          target,
          scenario
        )

        Result.new(
          success: true,
          state: state,
          events: [
            attack_event(
              type: event_type,
              attacker: attacker,
              target: target,
              attacker_position: attacker_position,
              target_position: target_position
            )
          ]
        )
      end

      def attack_event_type(attacker, target, scenario)
        if attacker["type"] == "headquarters" ||
            target["type"] == "headquarters"
          return "headquarters_attacked"
        end

        # Preserve the existing event for an attacker
        # destroyed before firing by a defending PT-SAU.
        if scenario == :ptsau_first && attacker["hp"] <= 0
          return "technique_destroyed"
        end

        "technique_attacked"
      end

      # ------------------------------------------------------------------
      # Common shot / counterattack
      # ------------------------------------------------------------------

      # The common shot mechanism is used by:
      # - ranged attacks;
      # - normal adjacent attacks;
      # - counterattacks;
      # - PT-SAU preemptive counterattacks;
      # - Headquarters attacks.
      #
      # This method never starts another counterattack.
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

      # A defending unit may counterattack once per opponent turn.
      #
      # This method is also used for the PT-SAU's first shot.
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

        return unless GameEngine::Rules::Position.adjacent?(
          attacker_position,
          target_position
        )

        # The flag is set only when the counterattack is performed.
        defender["has_counterattacked"] = true

        perform_shot(
          state,
          defender,
          attacker,
          attacker_position
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
      def apply_damage_to_headquarters(
        state,
        headquarters,
        damage
      )
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
        attack_event_type,
        attacker_position,
        target_position
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
            attack_event(
              type: attack_event_type,
              attacker: attacker,
              target: destroyed_headquarters,
              attacker_position: attacker_position,
              target_position: target_position
            ),
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
      # Events
      # ------------------------------------------------------------------

      def attack_event(
        type:,
        attacker:,
        target:,
        attacker_position:,
        target_position:
      )
        {
          type: type,
          attacker: {
            type: attacker["type"],
            player_id: attacker["player_id"],
            card_id: attacker["card_id"],
            name: attacker["name"],
            position: attacker_position
          },
          target: {
            type: target["type"],
            player_id: target["player_id"],
            card_id: target["card_id"],
            name: target["name"],
            position: target_position
          }
        }
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
    end
  end
end
