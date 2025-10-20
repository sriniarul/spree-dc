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
    elsif ENV['GOOGLE_OAUTH_CLIENT_ID'] && ENV['GOOGLE_OAUTH_CLIENT_SECRET']
      config.omniauth :google_oauth2,
                      ENV['GOOGLE_OAUTH_CLIENT_ID'],
                      ENV['GOOGLE_OAUTH_CLIENT_SECRET'],
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
end

# Configure User model for OAuth after initialization
Rails.application.config.after_initialize do
  if defined?(Devise) && defined?(Spree) && Spree.respond_to?(:user_class)
    user_class = Spree.user_class
    if user_class.respond_to?(:devise_modules) && user_class.devise_modules.present?
      unless user_class.devise_modules.include?(:omniauthable)
        user_class.devise :omniauthable, omniauth_providers: [:google_oauth2]
      end
    end
  end
end