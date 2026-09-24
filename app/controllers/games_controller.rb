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

    redirect_to game_path(
      @game,
      player_id: current_player_id
    )
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

    redirect_to game_path(
      @game,
      player_id: current_player_id
    )
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
		    from: [params[:from_row].to_i, params[:from_column].to_i],
		    to: [params[:to_row].to_i, params[:to_column].to_i]
		  }
		)

		result = GameEngine::Engine.new(@game.state).call(action)

		unless result.success?
		  render plain: result.error, status: :unprocessable_entity
		  return
		end

		@game.update!(state: result.state)

		redirect_to game_path(
		  @game,
		  player_id: current_player_id
		)
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

		redirect_to game_path(
		  @game,
		  player_id: current_player_id
		)
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
end
