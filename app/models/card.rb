class Card < ApplicationRecord
  belongs_to :nation
  has_one :technique

  validates :name, presence: true
  validates :card_type, presence: true
  validates :weight, presence: true, numericality: { only_integer: true, greater_than: 0 }
end
