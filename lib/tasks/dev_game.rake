namespace :dev do
  desc "Create a development game"
  task create_game: :environment do
    development_emails = [
      "dev.player1@example.com",
      "dev.player2@example.com"
    ]

    old_player_ids = Player
      .where(email: development_emails)
      .pluck(:id)

    unless old_player_ids.empty?
      development_game_ids = GamePlayer
        .where(player_id: old_player_ids)
        .distinct
        .pluck(:game_id)

      GamePlayer.where(game_id: development_game_ids).destroy_all
      Game.where(id: development_game_ids).destroy_all

      Player.where(id: old_player_ids).destroy_all
    end

    player_one = nil
    player_two = nil

    Player.transaction do
      player_one = Player.create!(
        email: "dev.player1@example.com",
        name: "Dev Player 1",
        password: "password"
      )

      player_two = Player.create!(
        email: "dev.player2@example.com",
        name: "Dev Player 2",
        password: "password"
      )

      StarterDecks::Create.call(player_one)
      StarterDecks::Create.call(player_two)
    end

    germany = Nation.find_by!(code: "germany")
    ussr = Nation.find_by!(code: "ussr")

    germany_hq = Card.find_by!(
      code: "germany_headquarters_operation_weiß"
    )

    ussr_hq = Card.find_by!(
      code: "ussr_headquarters_west_front"
    )

    germany_deck = player_one.decks.find_by!(
      headquarters_card: germany_hq
    )

    ussr_deck = player_two.decks.find_by!(
      headquarters_card: ussr_hq
    )

    game = Game.create!

    GamePlayer.create!(
      game: game,
      player: player_one,
      nation: germany,
      deck: germany_deck,
      headquarters_card: germany_hq
    )

    GamePlayer.create!(
      game: game,
      player: player_two,
      nation: ussr,
      deck: ussr_deck,
      headquarters_card: ussr_hq
    )

    GameEngine::StartGame.call(game)

    puts
    puts "Development game created."
    puts "Game ID: #{game.id}"
    puts
    puts "Player 1:"
    puts "  Email: dev.player1@example.com"
    puts "  Password: password"
    puts
    puts "Player 2:"
    puts "  Email: dev.player2@example.com"
    puts "  Password: password"
    puts
    puts "Open:"
    puts "http://localhost:3000/games/#{game.id}"
    puts
    puts "To test both players, log in as the corresponding player in separate browser sessions."
  end
end
