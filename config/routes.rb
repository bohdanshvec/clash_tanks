Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  mount ActionCable.server => "/cable"

  get "games/:id", to: "games#show", as: :game
  post "games/:id/end_turn", to: "games#end_turn", as: :end_turn
  post "games/:id/play_card", to: "games#play_card", as: :play_card
  post "games/:id/move", to: "games#move", as: :move
  post "games/:id/attack", to: "games#attack", as: :attack
end
