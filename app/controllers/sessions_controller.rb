class SessionsController < ApplicationController
  def new
  end

  def create
    player = Player.find_by(email: params[:email])

    if player&.authenticate(params[:password])
      session[:player_id] = player.id
      redirect_to root_path
    else
      flash.now[:alert] = "Неверный email или пароль."
      render :new, status: :unprocessable_entity
    end
  end
  
	def destroy
		reset_session
		redirect_to root_path
	end
end
