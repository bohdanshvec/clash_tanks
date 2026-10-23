class RegistrationsController < ApplicationController
  around_action :use_ukrainian_locale

  def new
    @player = Player.new
  end

  def create
    @player = Player.new(player_params)

    Player.transaction do
      @player.save!
      StarterDecks::Create.call(@player)
    end

    redirect_to root_path, notice: "Реєстрацію успішно завершено.", status: :see_other
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  private

  def use_ukrainian_locale(&action)
    I18n.with_locale(:uk, &action)
  end

  def player_params
    params.expect(player: [:email, :name, :password, :password_confirmation])
  end
end