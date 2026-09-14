class CardAbility < ApplicationRecord
  belongs_to :card
  belongs_to :ability

  validates :card_id, uniqueness: { scope: :ability_id }
end
