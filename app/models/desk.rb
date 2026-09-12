class Deck < ApplicationRecord
  belongs_to :player
  belongs_to :nation

  has_many :deck_cards, dependent: :destroy
  has_many :cards, through: :deck_cards

  validates :name, presence: true

  def card_count
    deck_cards.sum(:quantity)
  end
end
