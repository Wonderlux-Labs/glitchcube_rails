Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  mount MissionControl::Jobs::Engine, at: "/jobs"

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Home Assistant integration routes
  namespace :api do
    namespace :v1 do
      # New conversation orchestrator route (matches HASS agent)
      post "conversation", to: "conversation#handle"
      post "conversation/proactive", to: "conversation#proactive"
      post "conversation/persona_arrival", to: "conversation#persona_arrival"

      namespace :home_assistant do
        get "health", to: "home_assistant#health"
        get "entities", to: "home_assistant#entities"

        # Generic world state service trigger
        post "world_state/trigger", to: "home_assistant#trigger_world_state_service"
      end

      # Summary routes
      get "summaries/recent", to: "summaries#recent"

      # Performance mode routes
      post "performance_mode/start", to: "performance_mode#start"
      post "performance_mode/stop", to: "performance_mode#stop"
      get "performance_mode/status", to: "performance_mode#status"
      post "performance_mode/interrupt", to: "performance_mode#interrupt"

      # GPS routes
      get "gps/location", to: "gps#location"
      get "gps/coords", to: "gps#coords"
      get "gps/proximity", to: "gps#proximity"
      get "gps/home", to: "gps#home"
      get "gps/history", to: "gps#history"
      post "gps/simulate_movement", to: "gps#simulate_movement"
      get "gps/movement_status", to: "gps#movement_status"
      post "gps/set_destination", to: "gps#set_destination"
      post "gps/stop_movement", to: "gps#stop_movement"
      get "gps/cube_current_loc", to: "gps#cube_current_loc"
      get "gps/landmarks", to: "gps#landmarks"

      # Burning Man quest routes
      namespace :burning_man do
        post "quest/progress", to: "burning_man#update_quest_progress"
        get "quest/status", to: "burning_man#quest_status"
      end

      # GIS/Map data routes
      resources :gis, only: [] do
        collection do
          get "streets"
          get "blocks"
          get "initial"
          get "trash_fence"
          get "landmarks/nearby", to: "gis#landmarks_nearby"
        end
      end
    end
  end

  # Main health endpoint (matches existing HASS sensor expectations)
  get "health", to: "health#show"

  # Shorter routes for direct Home Assistant access
  get "ha/health", to: "home_assistant#health"
  get "ha/entities", to: "home_assistant#entities"
  post "ha/world_state/trigger", to: "home_assistant#trigger_world_state_service"

  # GPS map view
  get "gps", to: "gps#map"

  # Performance mode web interface
  get "performance", to: "performance#index"
  post "performance/start", to: "performance#start"
  post "performance/stop", to: "performance#stop"
  get "performance/status", to: "performance#status"

  # Admin dashboard for development monitoring
  namespace :admin do
    root "dashboard#index"

    resources :conversations, only: [ :index, :show ] do
      member do
        get :timeline
        get :tools
      end
    end

    resources :memories, only: [ :index, :show ] do
      collection do
        get :search
        get :by_type
      end
    end

    get "world_state", to: "world_state#index"
    get "world_state/history", to: "world_state#history"
    post "world_state/trigger/:service", to: "world_state#trigger", as: :trigger_world_state_service

    resources :prompts, only: [ :index, :show ] do
      collection do
        get :analytics
        get :models
      end
    end

    get "system", to: "system#index"
    get "system/health", to: "system#health"

    resources :people, only: [ :index, :show, :edit, :update, :destroy ] do
      collection do
        get :search
      end
    end

    resources :events, only: [ :index, :show ] do
      collection do
        get :timeline
        get :search
      end
    end

    resources :summaries, only: [ :index, :show ] do
      collection do
        get :analytics
        get :search
      end
    end

    resources :facts, only: [ :index, :show ] do
      collection do
        get :search
      end
    end
  end

  # Defines the root path route ("/")
  # root "posts#index"
end
