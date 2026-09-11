class Nation < ApplicationRecord
  has_many :cards
  has_many :game_players

  validates :name, presence: true
  validates :code, presence: true, uniqueness: true
end
