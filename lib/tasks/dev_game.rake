namespace :dev do
  desc "Create a development game for Stage 15 UI"
  task create_game: :environment do
    player_one = Player.find(1)
    player_two = Player.find(2)

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
      name: "Stage 15 Germany"
    )

    ussr_deck = Deck.create!(
      player: player_two,
      nation: ussr,
      name: "Stage 15 USSR"
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
    puts "Player 1 ID: #{player_one.id}"
    puts "Player 2 ID: #{player_two.id}"
    puts
    puts "Open:"
    puts "http://localhost:3000/games/#{game.id}?player_id=#{player_one.id}"
    puts "http://localhost:3000/games/#{game.id}?player_id=#{player_two.id}"
  end
end
