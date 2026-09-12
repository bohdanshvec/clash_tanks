class Technique < ApplicationRecord
  TECHNIQUE_TYPES = %w[
    light_tank
    medium_tank
    heavy_tank
    tank_destroyer
    artillery
  ].freeze

  MOVEMENT_TYPES = %w[
    orthogonal
    diagonal
  ].freeze

  belongs_to :card

  has_many :technique_abilities
  has_many :abilities, through: :technique_abilities

  validates :technique_type, presence: true, inclusion: { in: TECHNIQUE_TYPES }
  validates :attack_range, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :movement_count, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :movement_type, presence: true, inclusion: { in: MOVEMENT_TYPES }
  validates :firepower, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :hp, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :fuel, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
