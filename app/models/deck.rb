class Deck < ApplicationRecord
  DECK_SIZE = 10

  belongs_to :player
  belongs_to :nation
  belongs_to :headquarters_card, class_name: "Card"

  has_many :deck_cards, dependent: :destroy
  has_many :cards, through: :deck_cards

  validates :name, presence: true

  validate :headquarters_card_is_headquarters
  validate :headquarters_card_belongs_to_nation
  validate :card_count_does_not_exceed_limit

  def card_count
    deck_cards.sum(:quantity)
  end

  def complete?
    headquarters_card.present? && card_count == DECK_SIZE
  end

  def weight
    deck_cards.joins(:card).sum("cards.weight * deck_cards.quantity")
  end

  private

  def headquarters_card_is_headquarters
    return if headquarters_card.nil?
    return if headquarters_card.card_type == "headquarters"

    errors.add(:headquarters_card, "must be a headquarters card")
  end

  def headquarters_card_belongs_to_nation
    return if headquarters_card.nil? || nation.nil?
    return if headquarters_card.nation_id == nation_id

    errors.add(:headquarters_card, "must belong to the same nation as the deck")
  end

  def card_count_does_not_exceed_limit
    return if card_count <= DECK_SIZE

    errors.add(:base, "cannot contain more than #{DECK_SIZE} cards")
  end
end
