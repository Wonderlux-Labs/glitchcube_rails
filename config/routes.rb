Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Home Assistant integration routes
  namespace :api do
    namespace :v1 do
      # New conversation orchestrator route (matches HASS agent)
      post 'conversation', to: 'conversation#handle'
      
      namespace :home_assistant do
        post 'conversation/process', to: 'home_assistant#conversation_process'
        get 'health', to: 'home_assistant#health'
        get 'entities', to: 'home_assistant#entities'
      end

      # GPS routes
      get 'gps/location', to: 'gps#location'
      get 'gps/coords', to: 'gps#coords'
      get 'gps/proximity', to: 'gps#proximity'
      get 'gps/home', to: 'gps#home'
      get 'gps/history', to: 'gps#history'
      post 'gps/simulate_movement', to: 'gps#simulate_movement'
      get 'gps/cube_current_loc', to: 'gps#cube_current_loc'
      get 'gps/landmarks', to: 'gps#landmarks'

      # GIS/Map data routes  
      resources :gis, only: [] do
        collection do
          get 'streets'
          get 'blocks'
          get 'initial'
          get 'trash_fence'
          get 'landmarks/nearby', to: 'gis#landmarks_nearby'
        end
      end
    end
  end
  
  # Main health endpoint (matches existing HASS sensor expectations)
  get 'health', to: 'health#show'
  
  # Shorter routes for direct Home Assistant access
  post 'ha/conversation', to: 'home_assistant#conversation_process'
  get 'ha/health', to: 'home_assistant#health'
  get 'ha/entities', to: 'home_assistant#entities'

  # GPS map view
  get 'gps', to: 'gps#map'

  # SolidQueue web UI for job monitoring
  mount SolidQueue::Engine, at: "/jobs"

  # Defines the root path route ("/")
  # root "posts#index"
end
