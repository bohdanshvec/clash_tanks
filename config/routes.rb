Rails.application.routes.draw do
	root "pages#home"
	
  get "up" => "rails/health#show", as: :rails_health_check

  mount ActionCable.server => "/cable"
  
  get "rules", to: "pages#rules", as: :rules
	get "play", to: "pages#play", as: :play
	get "decks", to: "pages#decks", as: :decks
	get "statistics", to: "pages#statistics", as: :statistics
		
  get "register", to: "registrations#new", as: :register
	post "register", to: "registrations#create"
	
	get "login", to: "sessions#new", as: :login
	post "login", to: "sessions#create"
	delete "logout", to: "sessions#destroy", as: :logout

  get "games/:id", to: "games#show", as: :game
  post "games/:id/end_turn", to: "games#end_turn", as: :end_turn
  post "games/:id/play_card", to: "games#play_card", as: :play_card
  post "games/:id/move", to: "games#move", as: :move
  post "games/:id/attack", to: "games#attack", as: :attack
  post "games/:id/surrender", to: "games#surrender", as: :surrender
end
