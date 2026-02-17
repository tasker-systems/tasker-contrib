Rails.application.routes.draw do
  resources :orders, only: [:create, :show] do
    collection do
      post :create_async
    end
  end

  namespace :analytics do
    resources :jobs, only: [:create, :show]
  end

  namespace :services do
    resources :requests, only: [:create, :show]
  end

  namespace :compliance do
    resources :checks, only: [:create, :show]
  end

  # Health check
  get '/health', to: proc { [200, {}, [{ status: 'ok' }.to_json]] }
end
