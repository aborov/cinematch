Rails.application.routes.draw do
  # devise_for :admin_users, ActiveAdmin::Devise.config
  ActiveAdmin.routes(self)

  root to: "pages#landing"
  # get 'pages/landing'

  devise_for :users, controllers: {
    passwords: "users/passwords",
    registrations: "users/registrations",
  }

  # root to: "recommendations#index"

  resources :users, only: [:show, :edit, :update] do
    member do
      get "profile"
    end
  end

  resources :surveys, only: [:index, :create]
  resources :user_preferences, only: [:edit, :update]
  resources :recommendations, only: [:index, :show]
end
