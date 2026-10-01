class PagesController < ApplicationController
  def home
  end

  def rules
  end

  def play
  end

  def decks
  end

  def statistics
    redirect_to root_path unless current_player
  end
end
