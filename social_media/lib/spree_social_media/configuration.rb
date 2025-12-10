module SpreeSocialMedia
  class Configuration
    attr_accessor :facebook_app_id, :facebook_app_secret
    attr_accessor :instagram_app_id, :instagram_app_secret
    attr_accessor :whatsapp_app_id, :whatsapp_app_secret, :whatsapp_phone_number_id
    attr_accessor :youtube_client_id, :youtube_client_secret
    attr_accessor :tiktok_client_key, :tiktok_client_secret

    # General configuration
    attr_accessor :default_post_template
    attr_accessor :enable_analytics_collection
    attr_accessor :analytics_sync_frequency
    attr_accessor :max_retry_attempts
    attr_accessor :rate_limit_buffer
    attr_accessor :default_image_quality
    attr_accessor :enable_webhook_verification

    def initialize
      @facebook_app_id = Rails.application.credentials.dig(:facebook, :app_id) || ENV['FACEBOOK_APP_ID']
      @facebook_app_secret = Rails.application.credentials.dig(:facebook, :app_secret) || ENV['FACEBOOK_APP_SECRET']
      @instagram_app_id = Rails.application.credentials.dig(:instagram, :app_id) || ENV['INSTAGRAM_APP_ID']
      @instagram_app_secret = Rails.application.credentials.dig(:instagram, :app_secret) || ENV['INSTAGRAM_APP_SECRET']
      @whatsapp_app_id = Rails.application.credentials.dig(:whatsapp, :app_id) || ENV['WHATSAPP_APP_ID']
      @whatsapp_app_secret = Rails.application.credentials.dig(:whatsapp, :app_secret) || ENV['WHATSAPP_APP_SECRET']
      @whatsapp_phone_number_id = Rails.application.credentials.dig(:whatsapp, :phone_number_id) || ENV['WHATSAPP_PHONE_NUMBER_ID']
      @youtube_client_id = Rails.application.credentials.dig(:google, :client_id) || ENV['GOOGLE_CLIENT_ID']
      @youtube_client_secret = Rails.application.credentials.dig(:google, :client_secret) || ENV['GOOGLE_CLIENT_SECRET']
      @tiktok_client_key = Rails.application.credentials.dig(:tiktok, :client_key) || ENV['TIKTOK_CLIENT_KEY']
      @tiktok_client_secret = Rails.application.credentials.dig(:tiktok, :client_secret) || ENV['TIKTOK_CLIENT_SECRET']

      # Default configurations
      @default_post_template = 'Check out this amazing product: {{product_name}} - {{product_description}} {{product_url}} #{{store_name}} #ecommerce'
      @enable_analytics_collection = true
      @analytics_sync_frequency = 1.hour
      @max_retry_attempts = 3
      @rate_limit_buffer = 0.1
      @default_image_quality = 85
      @enable_webhook_verification = true
    end

    def facebook_configured?
      facebook_app_id.present? && facebook_app_secret.present?
    end

    def instagram_configured?
      instagram_app_id.present? && instagram_app_secret.present?
    end

    def whatsapp_configured?
      whatsapp_app_id.present? && whatsapp_app_secret.present? && whatsapp_phone_number_id.present?
    end

    def youtube_configured?
      youtube_client_id.present? && youtube_client_secret.present?
    end

    def tiktok_configured?
      tiktok_client_key.present? && tiktok_client_secret.present?
    end
  end
end