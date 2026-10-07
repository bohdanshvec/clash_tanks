class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :touch_guest_activity

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  helper_method :current_player
  helper_method :current_player_id
  helper_method :guest_player?
  helper_method :registered_player?

  private

  def current_player
    @current_player ||= Player.find_by(id: session[:player_id])
  end

  def current_player_id
    current_player&.id&.to_s
  end

  def guest_player?
    current_player&.guest?
  end

  def registered_player?
    current_player&.registered?
  end

  def player_in_game?(game)
    game.game_players.exists?(player_id: current_player_id)
  end

  def require_registered_player!
    unless current_player
      redirect_to login_path
      return
    end

    return unless guest_player?

    render_forbidden
  end

  def touch_guest_activity
    player = current_player
    return unless player&.guest?

    player.update_column(:last_seen_at, Time.current)
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
