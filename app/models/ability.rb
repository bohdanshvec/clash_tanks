class Ability < ApplicationRecord
  has_many :technique_abilities
  has_many :techniques, through: :technique_abilities

  validates :name, presence: true
  validates :code, presence: true, uniqueness: true
end
