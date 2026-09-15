class GamePlayer < ApplicationRecord
  belongs_to :game
  belongs_to :player
  belongs_to :nation
  belongs_to :deck
  belongs_to :headquarters_card, class_name: "Card"

  validate :headquarters_card_is_headquarters
  validate :headquarters_card_belongs_to_player_nation

  private

  def headquarters_card_is_headquarters
    return if headquarters_card.nil? || headquarters_card.card_type == "headquarters"

    errors.add(:headquarters_card, "must be a headquarters card")
  end

  def headquarters_card_belongs_to_player_nation
    return if headquarters_card.nil? || nation.nil?
    return if headquarters_card.nation_id == nation_id

    errors.add(:headquarters_card, "must belong to the same nation as the game player")
  end
end
