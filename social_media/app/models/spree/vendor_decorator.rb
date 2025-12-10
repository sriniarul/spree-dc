module Spree
  module VendorDecorator
    def self.prepended(base)
      base.class_eval do
        # Social media associations
        has_many :social_media_accounts, class_name: 'Spree::SocialMediaAccount', dependent: :destroy
        has_many :social_media_posts, through: :social_media_accounts, class_name: 'Spree::SocialMediaPost'
        has_many :campaigns, class_name: 'Spree::Campaign', dependent: :destroy
        has_many :hashtag_sets, class_name: 'Spree::HashtagSet', dependent: :destroy
        has_many :social_media_templates, class_name: 'Spree::SocialMediaTemplate', dependent: :destroy

        # Platform-specific associations
        has_many :facebook_accounts, -> { where(platform: 'facebook') },
                 class_name: 'Spree::SocialMediaAccount'
        has_many :instagram_accounts, -> { where(platform: 'instagram') },
                 class_name: 'Spree::SocialMediaAccount'
        has_many :whatsapp_accounts, -> { where(platform: 'whatsapp') },
                 class_name: 'Spree::SocialMediaAccount'
        has_many :youtube_accounts, -> { where(platform: 'youtube') },
                 class_name: 'Spree::SocialMediaAccount'
        has_many :tiktok_accounts, -> { where(platform: 'tiktok') },
                 class_name: 'Spree::SocialMediaAccount'

        # Active accounts only
        has_many :active_social_media_accounts, -> { active },
                 class_name: 'Spree::SocialMediaAccount'
      end
    end

    # Social media related methods
    def has_social_media_presence?
      social_media_accounts.active.any?
    end

    def connected_platforms
      social_media_accounts.active.pluck(:platform).uniq
    end

    def platform_connected?(platform)
      social_media_accounts.active.where(platform: platform).exists?
    end

    def get_account_for_platform(platform)
      social_media_accounts.active.find_by(platform: platform)
    end

    def social_media_reach
      social_media_accounts.active.sum(:followers_count)
    end

    def total_social_media_posts
      social_media_posts.posted.count
    end

    def social_media_engagement_rate
      posts = social_media_posts.posted.includes(:social_media_analytics)
      return 0 if posts.empty?

      total_impressions = 0
      total_engagements = 0

      posts.each do |post|
        analytics = post.social_media_analytics.sum_by_metric
        total_impressions += analytics['impressions'] || 0
        total_engagements += (analytics['likes'] || 0) + (analytics['comments'] || 0) + (analytics['shares'] || 0)
      end

      return 0 if total_impressions.zero?

      ((total_engagements.to_f / total_impressions) * 100).round(2)
    end

    # Campaign methods
    def active_campaigns
      campaigns.active
    end

    def scheduled_posts_count
      social_media_posts.scheduled.count
    end

    # Auto-posting configuration
    def auto_posting_enabled_for?(platform)
      account = get_account_for_platform(platform)
      account&.auto_post_enabled?
    end

    def enable_auto_posting_for!(platform)
      account = get_account_for_platform(platform)
      account&.update!(auto_post_enabled: true)
    end

    def disable_auto_posting_for!(platform)
      account = get_account_for_platform(platform)
      account&.update!(auto_post_enabled: false)
    end

    # Analytics methods
    def social_media_analytics_summary(date_range = 30.days.ago..Date.current)
      analytics = Spree::SocialMediaAnalytics.joins(:social_media_account)
                                            .where(spree_social_media_accounts: { vendor_id: id })
                                            .where(date: date_range)

      {
        total_impressions: analytics.sum(:impressions),
        total_likes: analytics.sum(:likes),
        total_comments: analytics.sum(:comments),
        total_shares: analytics.sum(:shares),
        total_clicks: analytics.sum(:clicks),
        platforms_count: connected_platforms.count,
        top_platform: top_performing_platform(date_range)
      }
    end

    private

    def top_performing_platform(date_range)
      platform_performance = Spree::SocialMediaAnalytics
                            .joins(:social_media_account)
                            .where(spree_social_media_accounts: { vendor_id: id })
                            .where(date: date_range)
                            .group('spree_social_media_accounts.platform')
                            .sum(:impressions)

      platform_performance.max_by { |platform, impressions| impressions }&.first
    end
  end

  Vendor.prepend(VendorDecorator)
end