class RegistrationsController < ApplicationController
  def new
    @player = Player.new
  end

  def create
    @player = Player.new(player_params)

    Player.transaction do
      @player.save!
      StarterDecks::Create.call(@player)
    end

    redirect_to root_path, notice: "Регистрация успешно завершена."
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  private

  def player_params
    params.expect(player: [:email, :name, :password, :password_confirmation])
  end
end
