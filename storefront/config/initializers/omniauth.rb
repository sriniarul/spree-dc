Rails.application.config.to_prepare do
  # Configure OmniAuth for Google OAuth2
  if defined?(Devise)
    Devise.setup do |config|
      config.omniauth :google_oauth2,
        Rails.application.credentials.dig(:google, :client_id) || ENV['GOOGLE_OAUTH_CLIENT_ID'],
        Rails.application.credentials.dig(:google, :client_secret) || ENV['GOOGLE_OAUTH_CLIENT_SECRET'],
        {
          scope: 'email,profile',
          prompt: 'consent',
          image_aspect_ratio: 'square',
          image_size: 50,
          access_type: 'online',
          name: 'google'
        }
    end

    # Ensure User class includes OAuth support and omniauthable module
    if defined?(Spree::User) && !Spree::User.devise_modules.include?(:omniauthable)
      Spree::User.devise :omniauthable
    end

    # Include OAuth concern if not already included
    if defined?(Spree::UserOauth) && defined?(Spree::User) && !Spree::User.included_modules.include?(Spree::UserOauth)
      Spree::User.include Spree::UserOauth
    end
  end
end