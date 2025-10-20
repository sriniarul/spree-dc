# OAuth routes for Spree Storefront
if defined?(Devise) && Spree.user_class.respond_to?(:omniauth_providers)
  Spree::Core::Engine.add_routes do
    # Override the default Devise routes to use our custom controller
    devise_for Spree.user_class.model_name.singular_route_key.to_sym,
               class_name: Spree.user_class.to_s,
               controllers: {
                 omniauth_callbacks: 'spree/users/omniauth_callbacks'
               },
               skip: [:sessions, :passwords, :registrations, :confirmations, :unlocks],
               path_names: { sign_in: 'login', sign_out: 'logout' }
  end
end