class Ability < ApplicationRecord
  has_many :card_abilities
  has_many :cards, through: :card_abilities

  validates :name, presence: true
  validates :code, presence: true, uniqueness: true
end
