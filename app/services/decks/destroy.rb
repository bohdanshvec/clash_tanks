
module Decks
  class Destroy
    class Error < StandardError; end

    def self.call(deck:)
      new(deck: deck).call
    end

    def initialize(deck:)
      @deck = deck
      @cancelled_waiting_games = false
      @finished_games = []
    end

    def call
      Deck.transaction do
        deck.lock!

        referenced_game_ids.each do |game_id|
          game = Game.find(game_id)
          process_game!(game)
        end

        # Завершённые партии сохраняются,
        # но больше не зависят от удаляемой колоды.
        GamePlayer
          .where(deck_id: deck.id)
          .update_all(deck_id: nil)

        deck.destroy!
      end

      broadcast_updates

      deck
    end

    private

    attr_reader :deck

    def referenced_game_ids
      GamePlayer
        .where(deck_id: deck.id)
        .distinct
        .pluck(:game_id)
    end

    def process_game!(game)
      game.with_lock do
        game_player = game.game_players.find_by(deck_id: deck.id)

        next unless game_player

        case game.status
        when "waiting"
          cancel_waiting_game!(game)

        when "started"
          surrender_in_game!(game, game_player)

        when "finished"
          # Историю завершённой партии не изменяем.

        else
          raise Error, "Unknown game status: #{game.status}"
        end
      end
    end

    def cancel_waiting_game!(game)
      unless game.game_players.count == 1
        raise Error, "Waiting game must have exactly one player"
      end

      game.destroy!
      @cancelled_waiting_games = true
    end

    def surrender_in_game!(game, game_player)
      player_ids = game.game_players.pluck(:player_id)

      action = DecisionProviders::Human.new(
        player_id: game_player.player_id,
        type: "surrender"
      ).call

      result = GameActionRunner.call(
        game: game,
        action: action
      )

      unless result.success?
        raise Error, "Could not surrender in game ##{game.id}: #{result.error}"
      end

      @finished_games << [game.id, player_ids]
    end

    def broadcast_updates
      broadcast_waiting_games_refresh if @cancelled_waiting_games

      @finished_games.each do |game_id, player_ids|
        game = Game.find_by(id: game_id)
        next unless game

        player_ids.each do |player_id|
          Turbo::StreamsChannel.broadcast_refresh_to(
            [game, player_id]
          )
        end
      end
    rescue StandardError => error
      Rails.logger.error(
        "[Decks::Destroy] Broadcast failed: " \
        "#{error.class}: #{error.message}"
      )
    end

    def broadcast_waiting_games_refresh
      Game.where(status: "waiting").find_each do |game|
        Turbo::StreamsChannel.broadcast_refresh_to(game)
      end
    end
  end
end
