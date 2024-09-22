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
  get 'recommendations/check_status', to: 'recommendations#check_status'
  resources :watchlist_items, only: [:index, :create, :destroy, :update] do
    collection do
      get :status
    end
    member do
      patch :reposition
      patch :mark_watched
      patch :mark_unwatched
    end
  end
  get 'watchlist_items/count', to: 'watchlist_items#count'
  get 'watchlist_items/recent', to: 'watchlist_items#recent'

  get "contact", to: "pages#contact"
  post "send_contact_email", to: "pages#send_contact_email"
  get "terms", to: "pages#terms"
  get "privacy", to: "pages#privacy"
  get "data_deletion", to: "pages#data_deletion"
  get '/sitemap.xml.gz', to: 'sitemaps#show'
  get "/service-worker.js", to: "service_worker#service_worker"
  get "/manifest.json", to: "service_worker#manifest"
end
