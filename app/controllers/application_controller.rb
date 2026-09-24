class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  private

  def current_player_id
    params[:player_id]
  end

  def player_in_game?(game)
    game.game_players.exists?(player_id: current_player_id)
  end
end
