class Nation < ApplicationRecord
  has_many :cards
  has_many :game_players
  has_many :decks, dependent: :destroy

  validates :name, presence: true
  validates :code, presence: true, uniqueness: true
end
