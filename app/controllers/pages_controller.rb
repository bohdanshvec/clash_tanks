class PagesController < ApplicationController
  def home
  end

  def rules
  end

	def play
		if current_player
		  @decks = current_player.decks
		    .includes(
		      :nation,
		      :headquarters_card,
		      deck_cards: {
		        card: [
		          :nation,
		          :technique,
		          :platoon,
		          :headquarters,
		          :abilities
		        ]
		      }
		    )
		    .order(:name)
		    .select(&:complete?)
		else
		  @starter_decks = StarterDecks::Create::STARTER_DECKS.map do |definition|
		    headquarters_card = Card
		      .includes(:nation, :headquarters, :abilities)
		      .find_by!(code: definition[:headquarters_code])

		    cards = Card
		      .includes(
		        :nation,
		        :technique,
		        :platoon,
		        :headquarters,
		        :abilities
		      )
		      .where(code: definition[:card_codes])
		      .sort_by { |card| definition[:card_codes].index(card.code) }

		    {
		      name: definition[:name],
		      nation: headquarters_card.nation,
		      headquarters_card: headquarters_card,
		      cards: cards
		    }
		  end
		end
	end

	def decks
		if current_player
		  @decks = current_player.decks
		    .includes(
		      :nation,
		      :headquarters_card,
		      deck_cards: {
		        card: [
		          :nation,
		          :technique,
		          :platoon,
		          :headquarters,
		          :abilities
		        ]
		      }
		    )
		    .order(:name)
		else
		  @starter_decks = StarterDecks::Create::STARTER_DECKS.map do |definition|
		    headquarters_card = Card
		      .includes(:nation, :headquarters, :abilities)
		      .find_by!(code: definition[:headquarters_code])

		    cards = Card
		      .includes(
		        :nation,
		        :technique,
		        :platoon,
		        :headquarters,
		        :abilities
		      )
		      .where(code: definition[:card_codes])
		      .sort_by { |card| definition[:card_codes].index(card.code) }

		    {
		      name: definition[:name],
		      nation: headquarters_card.nation,
		      headquarters_card: headquarters_card,
		      cards: cards
		    }
		  end
		end
	end
  
  def cards
    @cards = Card
      .includes(:nation, :technique, :platoon, :headquarters, :abilities)
      .order(:card_type, :name)
  end

  def statistics
    redirect_to root_path unless current_player
  end
end
