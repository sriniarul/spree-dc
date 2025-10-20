# OAuth configuration for Devise
if defined?(Devise)
  Devise.setup do |config|
    # Add OAuth providers
    if Rails.application.credentials.google&.client_id && Rails.application.credentials.google&.client_secret
      config.omniauth :google_oauth2,
                      Rails.application.credentials.google.client_id,
                      Rails.application.credentials.google.client_secret,
                      {
                        scope: 'email,profile',
                        prompt: 'consent',
                        image_aspect_ratio: 'square',
                        image_size: 50,
                        access_type: 'online',
                        name: 'google_oauth2'
                      }
    end
  end

  # Add omniauthable module to devise configuration
  if Spree.user_class.respond_to?(:devise_modules)
    unless Spree.user_class.devise_modules.include?(:omniauthable)
      Spree.user_class.devise :omniauthable, omniauth_providers: [:google_oauth2]
    end
  end
end