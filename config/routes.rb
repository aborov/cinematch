Rails.application.routes.draw do
  get 'pages/landing'
  devise_for :users, controllers: {
                       registrations: "users/registrations",
                     }

  root to: "pages#landing"
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
