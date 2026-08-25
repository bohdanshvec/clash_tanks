class Technique < ApplicationRecord

	belongs_to :card

	has_many :technique_abilities
	has_many :abilities, through: :technique_abilities

end
