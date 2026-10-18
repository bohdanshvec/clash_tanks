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
      # Проверка допустимости атаки
      # ------------------------------------------------------------------

      def valid_attack?(attacker, target, attacker_position, target_position)
        Rules::AttackTarget.valid?(
          state: @state,
          attacker: attacker,
          target: target,
          attacker_position: attacker_position,
          target_position: target_position
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
      # Исполнение атаки
      # ------------------------------------------------------------------

      def execute_attack(attacker_position, target_position)
        new_state = @state.deep_dup

        attacker = object_at_in_state(new_state, attacker_position)
        target = object_at_in_state(new_state, target_position)

        attacker["has_attacked"] = true

        scenario = Rules::CombatType.call(
          attacker: attacker,
          target: target,
          attacker_position: attacker_position,
          target_position: target_position
        )

        combat_result = Attacks::CombatExecutor.call(
          state: new_state,
          attacker_position: attacker_position,
          target_position: target_position,
          scenario: scenario
        )

        finish_attack(
          new_state,
          combat_result[:attacker],
          combat_result[:target],
          attacker_position,
          target_position,
          scenario
        )
      end

      # ------------------------------------------------------------------
      # Формирование результата и завершение игры
      # ------------------------------------------------------------------

      def finish_attack(
        state,
        attacker,
        target,
        attacker_position,
        target_position,
        scenario
      )
        # Штаб атакующего может быть уничтожен ответным выстрелом.
        if attacker["type"] == "headquarters" && attacker["hp"] <= 0
          return finish_game_after_headquarters_destruction(
            state,
            target,
            attacker,
            "headquarters_attacked",
            target_position,
            attacker_position
          )
        end

        # Штаб защищающегося может быть уничтожен атакой.
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

        Result.new(
          success: true,
          state: state,
          events: [
            attack_event(
              type: attack_event_type(attacker, target, scenario),
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

        # Сохраняем существующий тип события, когда
        # защищающаяся ПТ-САУ уничтожила атакующего первой.
        if scenario == :ptsau_first && attacker["hp"] <= 0
          return "technique_destroyed"
        end

        "technique_attacked"
      end

      def finish_game_after_headquarters_destruction(
        state,
        attacker,
        destroyed_headquarters,
        event_type,
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
              type: event_type,
              attacker: attacker,
              target: destroyed_headquarters,
              attacker_position: attacker_position,
              target_position: target_position
            ),
            *finish_result.events
          ]
        )
      end

      # ------------------------------------------------------------------
      # События
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
      # Работа с состоянием
      # ------------------------------------------------------------------

      def own_object?(object)
        object["player_id"].to_s == @action.player_id.to_s
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
    end
  end
end
