Rails.application.routes.draw do
  # devise_for :admin_users, ActiveAdmin::Devise.config
  ActiveAdmin.routes(self)

  root to: "pages#landing"

  devise_for :users, controllers: {
            passwords: "users/passwords",
            registrations: "users/registrations",
          }

  resources :users, only: [:show, :edit, :update, :destroy] do
    member do
      get 'profile'
    end
  end

  get 'restore_account', to: 'users#restore_account_form'
  post 'restore_account', to: 'users#restore'

  resources :surveys, only: [:index, :create]
  resources :user_preferences, only: [:edit, :update]
  resources :recommendations, only: [:index, :show]
  get "contact", to: "pages#contact"
  post "send_contact_email", to: "pages#send_contact_email"
  get "terms", to: "pages#terms"
  get "privacy", to: "pages#privacy"
  get "data_deletion", to: "pages#data_deletion"
end
