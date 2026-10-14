class Game < ApplicationRecord
  has_many :game_players, dependent: :destroy
  has_many :players, through: :game_players

  enum :status, {
    waiting: "waiting",
    started: "started",
    finished: "finished"
  }

  enum :mode, {
    pvp: "pvp",
    ai: "ai"
  }

  after_initialize :set_default_status, if: :new_record?

  private

  def set_default_status
    self.status ||= "waiting"
    self.mode ||= "pvp"
  end
end
