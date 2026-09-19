class Card < ApplicationRecord
  belongs_to :nation

  has_one :technique, dependent: :destroy
  has_one :platoon, dependent: :destroy
  has_one :headquarters, dependent: :destroy

  has_many :card_abilities, dependent: :destroy
  has_many :abilities, through: :card_abilities

	validates :name, presence: true
	validates :code, presence: true, uniqueness: true
	validates :card_type, presence: true, inclusion: { in: %w[headquarters technique order platoon] }
	validates :weight, presence: true, numericality: { only_integer: true, greater_than: 0 }

	validates :price,
		presence: true,
		unless: -> { card_type == "headquarters" }

	validates :price,
		numericality: { only_integer: true, greater_than_or_equal_to: 0 },
		allow_nil: true
end
