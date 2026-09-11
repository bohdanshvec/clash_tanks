class GamePlayer < ApplicationRecord
  belongs_to :game
  belongs_to :player
  belongs_to :nation
end
