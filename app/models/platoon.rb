class Platoon < ApplicationRecord
  belongs_to :card

  validates :card_id, uniqueness: true

  validates :firepower,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  validates :hp,
            presence: true,
            numericality: { only_integer: true, greater_than: 0 }

  validates :armor,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  validates :fuel,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
