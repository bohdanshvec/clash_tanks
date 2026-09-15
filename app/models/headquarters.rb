class Headquarters < ApplicationRecord
  belongs_to :card

  validates :hp, numericality: { only_integer: true, greater_than: 0 }
  validates :firepower, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :fuel, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
