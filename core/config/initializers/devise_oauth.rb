begin
  if defined?(Devise)
    require 'omniauth-google-oauth2'
    require 'omniauth/rails_csrf_protection'

    # Configure OmniAuth settings
    if defined?(OmniAuth)
      OmniAuth.config.allowed_request_methods = [:post, :get]
      OmniAuth.config.silence_get_warning = true
    end

    # Configure OAuth credentials
    client_id = nil
    client_secret = nil

    # OAuth configuration is handled by the consuming application's Devise initializer
    # This allows proper middleware ordering and configuration flexibility
  end
rescue => e
  Rails.logger.warn "OAuth initialization failed: #{e.message}" if defined?(Rails.logger)
end