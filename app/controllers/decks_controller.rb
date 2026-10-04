class DecksController < ApplicationController
  before_action :require_current_player
  before_action :set_deck, only: [:edit, :update, :destroy]
  before_action :load_editor_data, only: [:new, :edit]

  def new
    @deck = current_player.decks.new
    @selected_quantities = {}
  end

  def create
    @deck = current_player.decks.new

    assign_deck_attributes

    Deck.transaction do
      @deck.save!
      sync_deck_cards!
    end

    redirect_to decks_path, notice: "Колода создана."
  rescue ActiveRecord::RecordInvalid => error
    prepare_form_after_error(error)
    render :new, status: :unprocessable_entity
  end

  def edit
    @selected_quantities = @deck.deck_cards
      .pluck(:card_id, :quantity)
      .to_h
  end

  def update
    assign_deck_attributes

    Deck.transaction do
      @deck.save!
      sync_deck_cards!
    end

    redirect_to decks_path, notice: "Колода сохранена."
  rescue ActiveRecord::RecordInvalid => error
    prepare_form_after_error(error)
    render :edit, status: :unprocessable_entity
  end

  def destroy
    @deck.destroy!

    redirect_to decks_path, notice: "Колода удалена."
  end

  private

  def set_deck
    @deck = current_player.decks.find(params[:id])
  end

  def load_editor_data
    @headquarters_cards = Card
      .includes(:nation, :headquarters)
      .where(card_type: "headquarters")
      .order(:nation_id, :name)

    @cards_by_nation = Card
      .includes(
        :nation,
        :technique,
        :platoon,
        :headquarters,
        :abilities
      )
      .where.not(card_type: "headquarters")
      .order(:nation_id, :card_type, :name)
      .group_by(&:nation_id)
  end

	def assign_deck_attributes
		headquarters_card =
		  if @deck.persisted?
		    @deck.headquarters_card
		  else
		    Card.find(deck_params[:headquarters_card_id])
		  end

		@deck.name = deck_params[:name]
		@deck.headquarters_card = headquarters_card
		@deck.nation = headquarters_card.nation
	end

  def sync_deck_cards!
    quantities = normalized_card_quantities

    total = quantities.values.sum

    if total > Deck::DECK_SIZE
      @deck.errors.add(
        :base,
        "колода не может содержать больше #{Deck::DECK_SIZE} карт"
      )

      raise ActiveRecord::RecordInvalid, @deck
    end

    @deck.deck_cards.delete_all

    quantities.each do |card_id, quantity|
      @deck.deck_cards.create!(
        card_id: card_id,
        quantity: quantity
      )
    end
  end

	def normalized_card_quantities
		(deck_params[:card_quantities] || {}).to_h.each_with_object({}) do |(card_id, quantity), result|
		  quantity = Integer(quantity, exception: false)

		  next if quantity.nil? || quantity.zero?

		  result[card_id.to_i] = quantity
		end
	end

  def prepare_form_after_error(error)
    @selected_quantities = card_quantities.to_h.transform_keys(&:to_i)

    unless error.record == @deck
      @deck.errors.add(
        :base,
        error.record.errors.full_messages.to_sentence
      )
    end

    load_editor_data
  end

  def card_quantities
    deck_params[:card_quantities] || {}
  end

  def deck_params
    params.require(:deck).permit(
      :name,
      :headquarters_card_id,
      card_quantities: {}
    )
  end

  def require_current_player
    redirect_to root_path unless current_player
  end
end
