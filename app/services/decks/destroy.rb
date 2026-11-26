
module Decks
  class Destroy
    Error = Change::Error

    def self.call(deck:)
      new(deck: deck).call
    end

    def initialize(deck:)
      @deck = deck
    end

    def call
      Change.call(deck: deck) do |locked_deck|
        locked_deck.destroy!
      end

      deck
    end

    private

    attr_reader :deck
  end
end
