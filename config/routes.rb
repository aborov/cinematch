Rails.application.routes.draw do
  # devise_for :admin_users, ActiveAdmin::Devise.config
  ActiveAdmin.routes(self)
  authenticate :admin_user do
    mount GoodJob::Engine => 'good_job'
  end

  # Job runner specific routes
  if Rails.env.job_runner?
    # Health check endpoint
    get 'health_check', to: 'job_runner#health_check'
    
    # API routes for job runner
    namespace :api do
      resources :job_runner, only: [] do
        collection do
          get 'health_check'
          get 'status'
          post 'run_job'
          post 'run_specific_job'
          get 'job_status/:job_id', action: :job_status, as: :job_status_runner
        end
      end
    end
    
    # Catch all other routes and redirect to main app
    root to: 'job_runner#index'
    match '*path', to: 'job_runner#index', via: :all
  else
    # Regular application routes
    root to: "pages#landing"

    # API routes for job runner status
    namespace :api do
      resources :job_runner, only: [] do
        collection do
          get 'status'
          post 'run_job'
          post 'run_specific_job'
          get 'job_status/:job_id', action: :job_status, as: :job_status
        end
      end
    end

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

  resources :surveys, only: [:index, :create] do
    collection do
      post :save_progress
      post :responses, to: 'survey_responses#create'
    end
  end
  
  get 'survey_results', to: 'surveys#results', as: :survey_results

  resources :user_preferences, only: [:edit, :update]
  get 'recommendations/check_status', to: 'recommendations#check_status'
  resources :recommendations, only: [:index, :show] do
    collection do
      get :check_status
      post :refresh
    end
  end

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
  get 'about', to: 'pages#about'
  get "data_deletion", to: "pages#data_deletion"
  get '/sitemap.xml.gz', to: 'sitemaps#show'
  get "/service-worker.js", to: "service_worker#service_worker"
  get "/manifest.json", to: "service_worker#manifest"

  get 'proxy_image', to: 'proxy#image'
  
  # Job runner API endpoints
  get 'health_check', to: 'api/job_runner#health_check'
  
  namespace :api do
    # Job runner API
    resources :job_runner, only: [] do
      collection do
        get 'health_check'
        post 'run_job'
        post 'run_specific_job'
        get 'job_status/:job_id', action: :job_status, as: :status
      end
    end
  end
end
