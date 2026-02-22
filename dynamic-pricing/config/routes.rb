Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      get '/pricing', to: 'pricing#index'
      get '/health', to: 'health#index'
    end
  end
end
