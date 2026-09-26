class GamesController < ApplicationController
  def show
    @game = Game.find(params[:id])

    unless player_in_game?(@game)
      head :forbidden
      return
    end

    @visible_state = GameEngine::VisibleState.call(
      state: @game.state,
      player_id: current_player_id
    )
  end

  def end_turn
    @game = Game.find(params[:id])

    unless player_in_game?(@game)
      head :forbidden
      return
    end

    action = GameEngine::Action.new(
      player_id: current_player_id,
      type: "end_turn"
    )

    result = GameEngine::Engine.new(@game.state).call(action)

    unless result.success?
      render plain: result.error, status: :unprocessable_entity
      return
    end

    @game.update!(state: result.state)

    broadcast_game_update

    respond_after_success
  end

  def play_card
    @game = Game.find(params[:id])

    unless player_in_game?(@game)
      head :forbidden
      return
    end

    action = GameEngine::Action.new(
      player_id: current_player_id,
      type: "play_card",
      payload: {
        card_id: params[:card_id],
        row: params[:row]&.to_i,
        column: params[:column]&.to_i,
        targets: build_targets
      }
    )

    result = GameEngine::Engine.new(@game.state).call(action)

    unless result.success?
      render plain: result.error, status: :unprocessable_entity
      return
    end

    @game.update!(state: result.state)

    broadcast_game_update

    respond_after_success
  end

  def move
    @game = Game.find(params[:id])

    unless player_in_game?(@game)
      head :forbidden
      return
    end

    action = GameEngine::Action.new(
      player_id: current_player_id,
      type: "move",
      payload: {
        from: [
          params[:from_row].to_i,
          params[:from_column].to_i
        ],
        to: [
          params[:to_row].to_i,
          params[:to_column].to_i
        ]
      }
    )

    result = GameEngine::Engine.new(@game.state).call(action)

    unless result.success?
      render plain: result.error, status: :unprocessable_entity
      return
    end

    @game.update!(state: result.state)

    broadcast_game_update

    respond_after_success
  end

  def attack
    @game = Game.find(params[:id])

    unless player_in_game?(@game)
      head :forbidden
      return
    end

    action = GameEngine::Action.new(
      player_id: current_player_id,
      type: "attack",
      payload: {
        attacker: [
          params[:attacker_row].to_i,
          params[:attacker_column].to_i
        ],
        target: [
          params[:target_row].to_i,
          params[:target_column].to_i
        ]
      }
    )

    result = GameEngine::Engine.new(@game.state).call(action)

    unless result.success?
      render plain: result.error, status: :unprocessable_entity
      return
    end

    @game.update!(state: result.state)

    broadcast_game_update

    respond_after_success
  end

  private

  def build_targets
    return [] unless params[:target].present?

    row, column = params[:target].split(",").map(&:to_i)

    [
      {
        row: row,
        column: column
      }
    ]
  end

  def broadcast_game_update
    @game.state["players"].keys.each do |player_id|
      visible_state = GameEngine::VisibleState.call(
        state: @game.state,
        player_id: player_id
      )

      Turbo::StreamsChannel.broadcast_update_to(
        [@game, player_id],
        target: "game-content",
        partial: "games/game",
        locals: {
          game: @game,
          visible_state: visible_state,
          current_player_id: player_id
        }
      )
    end
  end

  def respond_after_success
    respond_to do |format|
      format.turbo_stream { head :no_content }

      format.html do
        redirect_to game_path(
          @game,
          player_id: current_player_id
        )
      end
    end
  end
end
