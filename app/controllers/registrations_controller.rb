class RegistrationsController < ApplicationController
  def new
    @player = Player.new
  end

  def create
    @player = Player.new(player_params)

    if @player.save
      redirect_to root_path, notice: "Регистрация успешно завершена."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def player_params
    params.expect(player: [:email, :name, :password, :password_confirmation])
  end
end
