Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      get '/pricing', to: 'pricing#index'
      get '/health', to: 'health#index'
    end
  end

  match '/api/v1/pricing', to: 'application#method_not_allowed', via: :all
  match '/api/v1/health', to: 'application#method_not_allowed', via: :all
  match '*unmatched', to: 'application#not_found', via: :all
end
