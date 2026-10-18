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

  scope :registered_humans, -> {
    where(guest: false, ai: false)
  }

  scope :statistics_leaders, -> {
    registered_humans
      .where("battles_count > 0")
      .order(
        Arel.sql(
          "wins_count DESC, " \
          "(wins_count::numeric / battles_count) DESC, " \
          "battles_count DESC, id ASC"
        )
      )
      .limit(100)
  }

  def guest?
    guest
  end

  def registered?
    !guest? && !ai?
  end

  def ai?
    ai
  end

  def display_name
    name.presence || email.split("@").first
  end

  def win_rate
    return 0.0 if battles_count.zero?

    (wins_count * 100.0 / battles_count).round(2)
  end
end
