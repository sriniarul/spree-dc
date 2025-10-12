Spree::Core::Engine.routes.draw do
  # Vendor registration routes for storefront
  get '/vendors/register', to: 'vendor_registrations#new', as: :new_vendor_registration
  post '/vendors/register', to: 'vendor_registrations#create', as: :vendor_registrations
  get '/vendors/registration/success', to: 'vendor_registrations#success', as: :vendor_registration_success

  # Vendor public pages
  get '/vendors', to: 'vendors#index', as: :vendors
  get '/vendors/:id', to: 'vendors#show', as: :vendor

  namespace :admin do
    resources :vendors do
      member do
        patch :approve
        patch :reject
        patch :suspend
        patch :activate
      end
    end

    # Vendor-specific admin routes
    namespace :vendor do
      get '/', to: 'dashboard#show', as: :dashboard
      resources :products
      resources :orders, only: [:index, :show]
    end
  end
end