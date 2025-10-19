Spree::Core::Engine.routes.draw do
  namespace :api do
    namespace :push do
      get 'env', to: 'env#show'
      resources :subscriptions, only: [:create, :destroy]
    end
  end

  namespace :admin do
    resources :push_notifications, only: [:index, :new, :create] do
      collection do
        post :test
        get :analytics
      end
    end
  end
end