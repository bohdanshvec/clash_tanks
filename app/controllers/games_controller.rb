class GamesController < ApplicationController
  layout "game"

  def create
    unless current_player
      redirect_to login_path
      return
    end

		unless %w[pvp ai].include?(params[:mode])
			render plain: "Game mode is not available", status: :unprocessable_entity
			return
		end

    deck = current_player.decks.find(params[:deck_id])

		unless deck.complete?
			render plain: "Deck is not complete", status: :unprocessable_entity
			return
		end

		if params[:mode] == "ai"
			unless Matchmaking::AiDeckSelector.call(player_deck: deck)
				render plain: "No compatible AI deck", status: :unprocessable_entity
				return
			end

			game = Matchmaking::CreateAiGame.call(
				player: current_player,
				deck: deck
			)

			redirect_to game_path(game)
			return
		end

		Matchmaking::CleanupStaleWaitingGames.call

    existing_waiting_game = current_player
      .games
      .where(status: "waiting")
      .joins(:game_players)
      .find_by(game_players: { player_id: current_player.id })

    if existing_waiting_game
      redirect_to game_path(existing_waiting_game)
      return
    end

    waiting_game = Matchmaking::FindOpponent.call(
      player: current_player,
      deck: deck
    )

    if waiting_game
      joined_game = Matchmaking::Join.call(
        game: waiting_game,
        player: current_player,
        deck: deck
      )

      if joined_game
        broadcast_game_refresh(joined_game)
        broadcast_waiting_games_refresh

        redirect_to game_path(joined_game)
        return
      end
    end

    game = Game.new(
      status: "waiting",
      last_seen_at: Time.current
    )

    game.transaction do
      game.save!

      game.game_players.create!(
        player: current_player,
        nation: deck.nation,
        deck: deck,
        headquarters_card: deck.headquarters_card
      )
    end

    broadcast_waiting_games_refresh(except: game)

    redirect_to game_path(game)
  end

	def show
		@game = Game.find(params[:id])

		unless player_in_game?(@game)
		  render_forbidden
		  return
		end

		if @game.waiting?
		  @waiting_games = Game
		    .where(status: "waiting")
		    .joins(:game_players)
		    .includes(game_players: :deck)
		    .select { |game| game.game_players.size == 1 }
		    .reject { |game| game.id == @game.id }

		  render :waiting
		  return
		end

		@current_player_id = current_player_id

		@visible_state = GameEngine::VisibleState.call(
		  state: @game.state,
		  player_id: @current_player_id
		)
	end
	
	def run_ai_turn
		@game = Game.find(params[:id])

		unless player_in_game?(@game)
		  render_forbidden
		  return
		end

		unless @game.mode == "ai" && @game.started?
		  head :unprocessable_entity
		  return
		end

		run_ai_turns_if_needed(broadcast_each_action: true)

		head :no_content
	end

  def cancel_waiting
    game = Game.find(params[:id])

    unless current_player
      redirect_to login_path
      return
    end

    game.with_lock do
      unless game.waiting?
        render plain: "Game is not waiting", status: :unprocessable_entity
        return
      end

      unless game.game_players.exists?(player_id: current_player.id)
        render_forbidden
        return
      end

      unless game.game_players.count == 1
        render plain: "Game already has two players", status: :unprocessable_entity
        return
      end

      game.destroy!
    end

    broadcast_waiting_games_refresh

    redirect_to play_path
  end

  def waiting_heartbeat
    game = Game.find(params[:id])

    unless current_player
      head :unauthorized
      return
    end

    unless game.waiting?
      head :unprocessable_entity
      return
    end

    unless game.game_players.exists?(player_id: current_player.id)
      head :forbidden
      return
    end

    game.update!(last_seen_at: Time.current)

    Matchmaking::CleanupStaleWaitingGames.call

    head :no_content
  end

  def end_turn
    @game = Game.find(params[:id])

    unless player_in_game?(@game)
      render_forbidden
      return
    end

    return if reject_waiting_game_action!

    action = DecisionProviders::Human.new(
      player_id: current_player_id,
      type: "end_turn"
    ).call

    process_game_action(action)
  end

  def surrender
    @game = Game.find(params[:id])

    unless player_in_game?(@game)
      render_forbidden
      return
    end

    return if reject_waiting_game_action!

    action = DecisionProviders::Human.new(
      player_id: current_player_id,
      type: "surrender"
    ).call

    process_game_action(action)
  end

  def play_card
    @game = Game.find(params[:id])

    unless player_in_game?(@game)
      render_forbidden
      return
    end

    return if reject_waiting_game_action!

    action = DecisionProviders::Human.new(
      player_id: current_player_id,
      type: "play_card",
      payload: {
        card_id: params[:card_id],
        row: params[:row]&.to_i,
        column: params[:column]&.to_i,
        targets: build_targets
      }
    ).call

    process_game_action(action)
  end

  def move
    @game = Game.find(params[:id])

    unless player_in_game?(@game)
      render_forbidden
      return
    end

    return if reject_waiting_game_action!

    action = DecisionProviders::Human.new(
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
    ).call

    process_game_action(action)
  end

  def attack
    @game = Game.find(params[:id])

    unless player_in_game?(@game)
      render_forbidden
      return
    end

    return if reject_waiting_game_action!

    action = DecisionProviders::Human.new(
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
    ).call

    process_game_action(action)
  end

  private
  
	def run_ai_turns_if_needed(broadcast_each_action: false)
		return unless @game.started?
		return unless @game.state.present?

		state = @game.state
		current_player_id = state["current_player_id"].to_s

		return if current_player_id.empty?

		current_player = Player.find_by(id: current_player_id)

		return unless current_player&.ai?

		options = { game: @game }

		if broadcast_each_action
		  options[:on_action] = lambda do |action_events|
		    # Сервис вызывает callback после успешного сохранения действия.
		    # Перечитываем игру, чтобы отправить актуальное состояние.
		    @game.reload

		    broadcast_game_update(action_events)
		  end
		end

		result = Games::RunAiTurns.call(**options)

		unless result.success?
		  Rails.logger.error(
		    "[GamesController] AI turn failed for game ##{@game.id}: " \
		    "#{result.error}"
		  )
		end

		result
	rescue StandardError => e
		Rails.logger.error(
		  "[GamesController] Could not run AI turns for game ##{@game&.id}: " \
		  "#{e.class}: #{e.message}"
		)

		nil
	end

	def process_game_action(action)
		result = GameActionRunner.call(
		  game: @game,
		  action: action
		)

		unless result.success?
		  render plain: result.error, status: :unprocessable_entity
		  return
		end

		# Сначала публикуем результат действия человека.
		# Это позволяет другим открытым подключениям получить
		# обновление до завершения запросов к AI-провайдеру.
		events = Array(result.events).dup

		@game.reload
		broadcast_game_update(events)

		# Если после действия человека ход перешёл к ИИ,
		# каждое успешное действие ИИ будет отправлено отдельно.
		run_ai_turns_if_needed(broadcast_each_action: true)

		# Получаем окончательное состояние для ответа на запрос.
		@game.reload

		respond_after_success
	end

  def reject_waiting_game_action!
    return false unless @game.waiting? && @game.state.nil?

    render plain: "Game has not started", status: :unprocessable_entity
    true
  end

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

  def broadcast_game_update(events)
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
          current_player_id: player_id,
          events: events
        }
      )
    end
  end

  def respond_after_success
    respond_to do |format|
      format.turbo_stream { head :no_content }

      format.html do
        redirect_to game_path(@game)
      end
    end
  end

  def broadcast_game_refresh(game)
    Turbo::StreamsChannel.broadcast_refresh_to(game)
  end

  def broadcast_waiting_games_refresh(except: nil)
    games = Game
      .where(status: "waiting")
      .where.not(id: except&.id)

    games.find_each do |game|
      Turbo::StreamsChannel.broadcast_refresh_to(game)
    end
  end
end
