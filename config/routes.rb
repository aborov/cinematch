Rails.application.routes.draw do
  devise_for :users

  # This is a blank app! Pick your first screen, build out the RCAV, and go from there. E.g.:
  # get "/your_first_screen" => "pages#first"

  resources :users, only: [:show] # We handle user sign-up/sign-in with Devise
  resources :surveys, only: [:index, :show, :create]

  root to: "home#index"
end
