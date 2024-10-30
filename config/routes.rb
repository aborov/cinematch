Rails.application.routes.draw do
  # devise_for :admin_users, ActiveAdmin::Devise.config
  ActiveAdmin.routes(self)
  authenticate :admin_user do
    mount GoodJob::Engine => 'good_job'
  end

  root to: "pages#landing"

  devise_for :users, controllers: {
            passwords: "users/passwords",
            registrations: "users/registrations",
            sessions: "users/sessions"
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
  get 'recommendations/check_status', to: 'recommendations#check_status'
  resources :recommendations, only: [:index, :show]
  resources :watchlist_items do
    collection do
      get :status
      get :count
      get :recent
      post :rate
    end
    member do
      post :toggle_watched
    end
  end
  get 'watchlist_items/count', to: 'watchlist_items#count'
  get 'watchlist_items/recent', to: 'watchlist_items#recent'
  patch 'watchlist_items/:id/update_position', to: 'watchlist_items#update_position'

  get "contact", to: "pages#contact"
  post "send_contact_email", to: "pages#send_contact_email"
  get "terms", to: "pages#terms"
  get "privacy", to: "pages#privacy"
  get "data_deletion", to: "pages#data_deletion"
  get '/sitemap.xml.gz', to: 'sitemaps#show'
  get "/service-worker.js", to: "service_worker#service_worker"
  get "/manifest.json", to: "service_worker#manifest"
end
