class Nation < ApplicationRecord
  has_many :cards

  validates :name, presence: true
  validates :code, presence: true, uniqueness: true
end
