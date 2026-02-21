# frozen_string_literal: true

Rails.application.routes.draw do
  resources :orders, only: %i[create show] do
    collection do
      post :create_async
    end
  end

  namespace :analytics do
    resources :jobs, only: %i[create show]
  end

  namespace :services do
    resources :requests, only: %i[create show]
  end

  namespace :compliance do
    resources :checks, only: %i[create show]
  end

  # Health check
  get '/health', to: proc { [200, {}, [{ status: 'ok' }.to_json]] }
end
