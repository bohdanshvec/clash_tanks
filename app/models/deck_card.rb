class DeckCard < ApplicationRecord
  belongs_to :deck
  belongs_to :card

  validates :quantity,
            presence: true,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 1,
              less_than_or_equal_to: 3
            }

  validates :card_id, uniqueness: { scope: :deck_id }

  validate :card_belongs_to_deck_nation

  private

  def card_belongs_to_deck_nation
    return if deck.nil? || card.nil?

    if deck.nation_id != card.nation_id
      errors.add(:card, "must belong to the same nation as the deck")
    end
  end
end
