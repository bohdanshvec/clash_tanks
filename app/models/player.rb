class Player < ApplicationRecord
  has_secure_password

  has_many :game_players
  has_many :games, through: :game_players
  has_many :decks, dependent: :destroy

  validates :email, presence: true, uniqueness: true

  def display_name
    name.presence || email.split("@").first
  end
end
