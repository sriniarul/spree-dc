Rails.application.configure do
  config.to_prepare do
    Devise.setup do |config|
      config.omniauth :google_oauth2,
                      Rails.application.credentials.dig(:google, :client_id),
                      Rails.application.credentials.dig(:google, :client_secret),
                      {
                        scope: 'email,profile',
                        prompt: 'consent',
                        image_aspect_ratio: 'square',
                        image_size: 50
                      }
    end
  end
end