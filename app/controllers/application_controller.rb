class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  helper_method :current_player

  private

  def current_player
    @current_player ||= Player.find_by(id: session[:player_id])
  end

  def current_player_id
    current_player&.id&.to_s
  end

  def player_in_game?(game)
    game.game_players.exists?(player_id: current_player_id)
  end

  def render_not_found
    render file: Rails.public_path.join("404.html"),
           status: :not_found,
           layout: false
  end

  def render_forbidden
    render file: Rails.public_path.join("403.html"),
           status: :forbidden,
           layout: false
  end
end
