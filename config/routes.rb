Rails.application.routes.draw do
  # devise_for :admin_users, ActiveAdmin::Devise.config
  ActiveAdmin.routes(self)
  
  # Admin routes
  namespace :admin do
    get 'good_job_dashboard', to: 'good_job#dashboard'
    get 'good_job/:id', to: 'good_job#show', as: 'good_job_show'
    post 'good_job/:id/run', to: 'good_job#run', as: 'good_job_run'
    post 'good_job/:id/retry', to: 'good_job#retry', as: 'good_job_retry'
    delete 'good_job/:id', to: 'good_job#delete', as: 'good_job_delete'
    post 'good_job/:id/cancel', to: 'good_job#cancel', as: 'good_job_cancel'
    post 'good_job/run_job', to: 'good_job#run_job', as: 'good_job_run_job'
    
    # Fetcher service management routes
    get 'fetcher_service', to: 'fetcher_service#index'
    post 'fetcher_service/wake', to: 'fetcher_service#wake', as: 'wake_fetcher_service'
    post 'fetcher_service/test_job', to: 'fetcher_service#test_job', as: 'test_job_fetcher_service'
    
    # Admin routes
    resources :users
    resources :movies
    resources :tv_shows
    resources :genres
    resources :recommendations
    resources :watchlist_items
    resources :content_providers
  end
  
  authenticate :user, lambda { |u| u.admin? } do
    mount GoodJob::Engine => 'good_job'
  end

  root to: "pages#landing"

  devise_for :users, controllers: {
            passwords: 'users/passwords',
            registrations: 'users/registrations',
            sessions: 'users/sessions',
            confirmations: 'users/confirmations',
            unlocks: 'users/unlocks',
            omniauth_callbacks: 'users/omniauth_callbacks'
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

  # Profile and watchlist routes
  get 'profile', to: 'users#show'
  get 'profile/edit', to: 'users#edit'
  patch 'profile', to: 'users#update'
  
  get 'watchlist', to: 'watchlist_items#index'
  resources :watchlist_items, path: 'watchlist', only: [:create, :destroy] do
    collection do
      get 'unwatched_count'
      get 'count'
      get 'recent'
      get 'status'
      post 'rate'
    end
    member do
      post 'toggle_watched'
      post 'reposition'
    end
  end

  get "contact", to: "pages#contact"
  post "send_contact_email", to: "pages#send_contact_email"
  get "terms", to: "pages#terms"
  get "privacy", to: "pages#privacy"
  get "data_deletion", to: "pages#data_deletion"
  get '/sitemap.xml.gz', to: 'sitemaps#show'
  get "/service-worker.js", to: "service_worker#service_worker"
  get "/manifest.json", to: "service_worker#manifest"

  # Fetcher service routes
  get 'fetcher/ping', to: 'fetcher#ping'
  get 'fetcher/status', to: 'fetcher#status'
  post 'fetcher/fetch', to: 'fetcher#fetch'
  
  # Simple ping endpoint for health checks
  get 'ping', to: 'pages#ping'

  # Add a route for testing fetcher job routing
  get 'test/fetcher_job', to: 'test#test_fetcher_job'
  get 'test/run_test_fetcher_job', to: 'test#run_test_fetcher_job'
end
