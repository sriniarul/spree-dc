module Spree
  class SocialMediaAccount < Spree.base_class
    acts_as_paranoid

    include Spree::Metadata if defined?(Spree::Metadata)

    # Platform constants
    PLATFORMS = %w[facebook instagram whatsapp youtube tiktok].freeze
    STATUSES = %w[active inactive error pending_approval].freeze

    # Associations
    belongs_to :vendor, class_name: 'Spree::Vendor'
    has_many :social_media_posts, class_name: 'Spree::SocialMediaPost', dependent: :destroy
    has_many :social_media_analytics, class_name: 'Spree::SocialMediaAnalytics', dependent: :destroy
    # TODO: Add campaign associations when campaign functionality is implemented
    # has_many :campaign_posts, class_name: 'Spree::CampaignPost', dependent: :destroy
    # has_many :campaigns, through: :campaign_posts, source: :campaign, class_name: 'Spree::Campaign'

    # Validations
    validates :vendor_id, presence: true
    validates :platform, presence: true, inclusion: { in: PLATFORMS }
    validates :platform_user_id, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :platform, uniqueness: { scope: [:vendor_id, :platform_user_id], message: 'account already connected for this vendor' }

    # Scopes
    scope :active, -> { where(status: 'active') }
    scope :by_platform, ->(platform) { where(platform: platform) }
    scope :by_vendor, ->(vendor_id) { where(vendor_id: vendor_id) }
    scope :facebook_accounts, -> { where(platform: 'facebook') }
    scope :instagram_accounts, -> { where(platform: 'instagram') }
    scope :whatsapp_accounts, -> { where(platform: 'whatsapp') }
    scope :youtube_accounts, -> { where(platform: 'youtube') }
    scope :tiktok_accounts, -> { where(platform: 'tiktok') }

    # Callbacks
    before_validation :set_default_status, on: :create
    after_create :sync_platform_details
    after_update :handle_status_change

    # Token management
    def access_token_valid?
      expires_at.blank? || expires_at > Time.current
    end

    def refresh_access_token!
      case platform
      when 'facebook', 'instagram'
        refresh_facebook_token!
      when 'youtube'
        refresh_google_token!
      when 'tiktok'
        refresh_tiktok_token!
      else
        false
      end
    end

    # Platform-specific methods
    def platform_name
      platform.humanize
    end

    def display_name
      username.presence || platform_name
    end

    def display_name_with_platform
      "#{platform_name} - @#{username || platform_user_id}"
    end

    def profile_url
      case platform
      when 'facebook'
        "https://facebook.com/#{username}" if username.present?
      when 'instagram'
        "https://instagram.com/#{username}" if username.present?
      when 'youtube'
        "https://youtube.com/channel/#{platform_user_id}"
      when 'tiktok'
        "https://tiktok.com/@#{username}" if username.present?
      when 'whatsapp'
        "WhatsApp Business: #{phone_number}" if phone_number.present?
      end
    end

    # Status methods
    def active?
      status == 'active'
    end

    def inactive?
      status == 'inactive'
    end

    def error?
      status == 'error'
    end

    def pending_approval?
      status == 'pending_approval'
    end

    def activate!
      update!(status: 'active', last_error: nil)
    end

    def deactivate!
      update!(status: 'inactive')
    end

    def mark_error!(error_message)
      update!(status: 'error', last_error: error_message)
    end

    # Analytics methods
    def latest_analytics
      social_media_analytics.order(date: :desc).first
    end

    def total_followers
      latest_analytics&.followers_count || 0
    end

    def engagement_rate
      analytics = latest_analytics
      return 0 unless analytics && analytics.impressions > 0

      ((analytics.likes + analytics.comments + analytics.shares).to_f / analytics.impressions * 100).round(2)
    end

    # API interaction methods
    def post_to_platform(content, options = {})
      return false unless active? && access_token_valid?

      service_class = "Spree::SocialMedia::#{platform.camelize}PostService".constantize
      service_class.new(self).post(content, options)
    rescue => e
      mark_error!(e.message)
      false
    end

    def sync_analytics!
      return false unless active?

      service_class = "Spree::SocialMedia::#{platform.camelize}AnalyticsService".constantize
      service_class.new(self).sync_analytics
    rescue => e
      Rails.logger.error "Failed to sync analytics for #{platform} account #{id}: #{e.message}"
      false
    end

    private

    def set_default_status
      self.status ||= case platform
                      when 'whatsapp', 'tiktok'
                        'pending_approval'
                      else
                        'active'
                      end
    end

    def sync_platform_details
      Spree::SocialMedia::SyncAccountDetailsJob.perform_later(id)
    end

    def handle_status_change
      if saved_change_to_status?
        case status
        when 'active'
          Spree::SocialMedia::EnableAnalyticsSyncJob.perform_later(id)
        when 'inactive'
          Spree::SocialMedia::DisableAnalyticsSyncJob.perform_later(id)
        end
      end
    end

    # Token refresh methods
    def refresh_facebook_token!
      # Implementation for Facebook token refresh
      # This would use Facebook Graph API to refresh the token
      true
    end

    def refresh_google_token!
      # Implementation for Google OAuth token refresh
      # This would use Google OAuth2 to refresh the token
      true
    end

    def refresh_tiktok_token!
      # Implementation for TikTok token refresh
      # This would use TikTok API to refresh the token
      true
    end
  end
end