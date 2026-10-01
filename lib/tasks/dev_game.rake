namespace :dev do
  desc "Create a development game"
  task create_game: :environment do
    player_one = Player.find_or_create_by!(email: "dev.player1@example.com") do |player|
      player.name = "Dev Player 1"
      player.password = "password"
    end

    player_two = Player.find_or_create_by!(email: "dev.player2@example.com") do |player|
      player.name = "Dev Player 2"
      player.password = "password"
    end

    germany = Nation.find_by!(code: "germany")
    ussr = Nation.find_by!(code: "ussr")

    germany_hq = Card.find_by!(code: "germany_headquarters")
    ussr_hq = Card.find_by!(code: "ussr_headquarters")

    germany_codes = %w[
      germany_pz_ii_l_luchs
      germany_pz_iii_j
      germany_pz_iv_h
      germany_tiger_i
      germany_jagdpanther
      germany_hummel
      germany_tocnyj_vystrel
      germany_radioperekhvat
      germany_grenaderskij_vzvod
      germany_flak_88
    ]

    ussr_codes = %w[
      ussr_t_70
      ussr_t_34
      ussr_t_34_85
      ussr_is_2
      ussr_su_100
      ussr_su_26
      ussr_zalp_katyushi
      ussr_popolnenie
      ussr_strelkovyj_vzvod
      ussr_vzvod_ptr
    ]

    germany_deck = Deck.create!(
      player: player_one,
      nation: germany,
      name: "Development Germany"
    )

    ussr_deck = Deck.create!(
      player: player_two,
      nation: ussr,
      name: "Development USSR"
    )

    germany_codes.each do |code|
      DeckCard.create!(
        deck: germany_deck,
        card: Card.find_by!(code: code),
        quantity: 1
      )
    end

    ussr_codes.each do |code|
      DeckCard.create!(
        deck: ussr_deck,
        card: Card.find_by!(code: code),
        quantity: 1
      )
    end

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
