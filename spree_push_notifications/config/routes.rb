Spree::Core::Engine.routes.draw do
  namespace :api do
    namespace :push do
      get 'public-key', to: 'subscriptions#public_key'
      post 'subscribe', to: 'subscriptions#create'
      get 'test-push', to: 'subscriptions#test'
    end
  end

  namespace :admin do
    resources :push_notifications, only: [:index, :new, :create] do
      collection do
        post :test
      end
    end
  end
end