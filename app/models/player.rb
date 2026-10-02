class Player < ApplicationRecord
  has_secure_password

  has_many :game_players
  has_many :games, through: :game_players
  has_many :decks, dependent: :destroy

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email,
            presence: true,
            uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP }

  validates :password,
            length: { minimum: 8 },
            if: -> { password.present? }

  def display_name
    name.presence || email.split("@").first
  end
end
