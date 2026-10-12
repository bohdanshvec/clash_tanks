require "test_helper"
require "timeout"

class GameConcurrencyTest < ActiveSupport::TestCase
  # Потокам нужны отдельные соединения с БД.
  # Отключаем общую транзакцию теста, чтобы созданная запись
  # была доступна другим соединениям.
  self.use_transactional_tests = false

  test "with_lock prevents lost updates from concurrent threads" do
    game = Game.create!(
      status: :started,
      state: {
        "concurrency_test_counter" => 0
      }
    )

    game_id = game.id

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          locked_game = Game.find(game_id)

          locked_game.with_lock do
            counter = locked_game.state.fetch(
              "concurrency_test_counter"
            )

            # Создаём небольшое окно для пересечения потоков.
            sleep 0.1

            locked_game.update!(
              state: locked_game.state.merge(
                "concurrency_test_counter" => counter + 1
              )
            )
          end
        end
      end
    end

    threads.each(&:value)

    game.reload

    assert_equal(
      2,
      game.state.fetch("concurrency_test_counter"),
      "Оба обновления должны сохраниться без потери изменений"
    )
  ensure
    threads&.each do |thread|
      thread.kill if thread.alive?
      thread.join
    end

    game&.destroy!
  end
end


class GameControllerConcurrencyTest < ActionDispatch::IntegrationTest
  # Каждому HTTP-запросу нужно видеть созданные тестом записи.
  self.use_transactional_tests = false

  test "concurrent surrender requests leave the game finished" do
    game = nil
    nation = nil
    headquarters_card = nil
    players = []
    threads = []

    nation = Nation.create!(
      name: "Concurrency Test Nation",
      code: "concurrency_test_#{SecureRandom.hex(4)}"
    )

    headquarters_card = Card.create!(
      nation: nation,
      name: "Concurrency Test HQ",
      code: "concurrency_test_hq_#{SecureRandom.hex(4)}",
      card_type: "headquarters",
      weight: 1,
      price: nil
    )

    players = 2.times.map do
      player = create_player

      deck = Deck.create!(
        player: player,
        nation: nation,
        name: "Concurrency Test Deck",
        headquarters_card: headquarters_card
      )

      [player, deck]
    end

    player_one, deck_one = players[0]
    player_two, deck_two = players[1]

    game = Game.create!(
      status: :started,
      state: {
        "status" => "started",
        "turn_number" => 1,
        "current_player_id" => player_one.id,
        "turn_started_at" => Time.current.iso8601,
        "players" => {
          player_one.id.to_s => {
            "nation_id" => nation.id,
            "hand" => [],
            "deck" => [],
            "graveyard" => [],
            "platoons" => [nil, nil, nil, nil],
            "resources" => 0,
            "remaining_time" => 600,
            "empty_deck_draw_attempts" => 0
          },
          player_two.id.to_s => {
            "nation_id" => nation.id,
            "hand" => [],
            "deck" => [],
            "graveyard" => [],
            "platoons" => [nil, nil, nil, nil],
            "resources" => 0,
            "remaining_time" => 600,
            "empty_deck_draw_attempts" => 0
          }
        },
        "field" => GameEngine::GameState.empty_field
      }
    )

    GamePlayer.create!(
      game: game,
      player: player_one,
      nation: nation,
      deck: deck_one,
      headquarters_card: headquarters_card
    )

    GamePlayer.create!(
      game: game,
      player: player_two,
      nation: nation,
      deck: deck_two,
      headquarters_card: headquarters_card
    )

    # Создаём две независимые HTTP-сессии и авторизуем игроков
    # до запуска потоков. Это исключает зависание на авторизации.
    sessions = players.map do |player, _deck|
      session = ActionDispatch::Integration::Session.new(
        Rails.application
      )

      session.post login_path, params: {
        email: player.email,
        password: "password"
      }

      session
    end

    gate = Queue.new

    threads = sessions.map do |session|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          # Оба потока ждут, пока основной поток разрешит запросы.
          gate.pop

          session.post surrender_path(game)

          session.response.status
        end
      end
    end

    # Разрешаем обоим потокам отправить запросы.
    2.times { gate << true }

    statuses = Timeout.timeout(15) do
      threads.map(&:value)
    end

    assert(
      statuses.none? { |status| status >= 500 },
      "Неожиданная серверная ошибка: HTTP #{statuses.inspect}"
    )

    game.reload

    assert_equal "finished", game.status
    assert_equal "finished", game.state["status"]
  ensure
    threads&.each do |thread|
      thread.kill if thread.alive?
      thread.join
    end

    game&.destroy!

    players&.each do |player, _deck|
      player.destroy! if player&.persisted?
    end

    headquarters_card&.destroy! if headquarters_card&.persisted?
    nation&.destroy! if nation&.persisted?
  end
end
