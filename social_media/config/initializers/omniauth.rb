# frozen_string_literal: true

# NOTE: Instagram Login uses a custom OAuth flow (not OmniAuth)
# The Instagram API with Instagram Login requires:
# 1. Manual authorization URL generation
# 2. Custom token exchange endpoint (api.instagram.com, not graph.facebook.com)
# 3. Short-lived to long-lived token exchange
#
# Therefore, we handle Instagram OAuth manually in the controllers
# See: oauth_initiation_controller.rb and oauth_callbacks_controller.rb

Rails.application.config.middleware.use OmniAuth::Builder do
  # Facebook OAuth (optional - for Facebook Page posting)
  facebook_app_id = Rails.application.credentials.dig(:facebook, :app_id) || ENV['FACEBOOK_APP_ID']
  facebook_app_secret = Rails.application.credentials.dig(:facebook, :app_secret) || ENV['FACEBOOK_APP_SECRET']

  if facebook_app_id.present? && facebook_app_secret.present?
    provider :facebook, facebook_app_id, facebook_app_secret,
      scope: 'pages_show_list,pages_read_engagement,pages_manage_posts,pages_manage_metadata,pages_read_user_content',
      info_fields: 'id,name,email',
      display: 'page',
      auth_type: '',
      secure_image_url: true,
      image_size: 'large',
      callback_url: "#{ENV['APP_URL'] || 'http://localhost:3000'}/auth/facebook/callback"
  else
    Rails.logger.warn "Facebook OAuth not configured. Please set FACEBOOK_APP_ID and FACEBOOK_APP_SECRET environment variables or add them to Rails credentials."
  end

  # Google OAuth for YouTube integration
  google_client_id = Rails.application.credentials.dig(:google, :client_id) || ENV['GOOGLE_CLIENT_ID']
  google_client_secret = Rails.application.credentials.dig(:google, :client_secret) || ENV['GOOGLE_CLIENT_SECRET']

  if google_client_id.present? && google_client_secret.present?
    provider :google_oauth2, google_client_id, google_client_secret,
      scope: 'email,profile,https://www.googleapis.com/auth/youtube,https://www.googleapis.com/auth/youtube.upload,https://www.googleapis.com/auth/youtube.readonly,https://www.googleapis.com/auth/youtubepartner',
      access_type: 'offline',
      prompt: 'consent',
      callback_url: "#{ENV['APP_URL'] || 'http://localhost:3000'}/auth/google_oauth2/callback"
  else
    Rails.logger.warn "Google OAuth not configured. Please set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET environment variables or add them to Rails credentials."
  end

  # TikTok OAuth configuration would go here when needed
  # Note: TikTok requires business API access and manual approval
end

# Configure OmniAuth settings
OmniAuth.config.logger = Rails.logger
OmniAuth.config.allowed_request_methods = [:get, :post]

# Silence CSRF protection warning in development
# In production, ensure proper CSRF protection is implemented
OmniAuth.config.silence_get_warning = Rails.env.development? || Rails.env.test?
