module Spree
  class SocialMediaMilestone < Spree::Base
    belongs_to :social_media_account, class_name: 'Spree::SocialMediaAccount'
    belongs_to :social_media_post, class_name: 'Spree::SocialMediaPost', optional: true

    validates :milestone_type, presence: true
    validates :message, presence: true
    validates :achieved_at, presence: true

    scope :recent, -> { order(achieved_at: :desc) }
    scope :by_type, ->(type) { where(milestone_type: type) }
    scope :for_account, ->(account) { where(social_media_account: account) }
    scope :for_post, ->(post) { where(social_media_post: post) }
    scope :in_period, ->(start_date, end_date) { where(achieved_at: start_date..end_date) }

    def metrics_data_hash
      return {} unless metrics_data.present?

      JSON.parse(metrics_data)
    rescue JSON::ParserError
      {}
    end

    def category
      case milestone_type
      when /^followers_/
        'growth'
      when /^(likes_|comments_|shares_)/
        'engagement'
      when /^posts_/
        'content'
      when /^mentions_/
        'brand_awareness'
      when /^story_/
        'stories'
      when /^engagement_rate_/
        'performance'
      when /_streak_/
        'consistency'
      when /^first_/
        'achievement'
      else
        'special'
      end
    end

    def celebration_message
      case category
      when 'growth'
        "🎉 Congratulations on reaching this follower milestone!"
      when 'engagement'
        "🔥 Your content is really connecting with your audience!"
      when 'content'
        "📸 You're building an amazing content library!"
      when 'brand_awareness'
        "🌟 Your brand is getting noticed!"
      when 'stories'
        "📱 Your stories are captivating viewers!"
      when 'performance'
        "📈 Your engagement rate is impressive!"
      when 'consistency'
        "⚡ Your consistency is paying off!"
      when 'achievement'
        "🏆 Welcome to the journey of social media success!"
      else
        "🎯 Special milestone achieved!"
      end
    end

    def share_worthy?
      major_milestones = [
        'followers_1k', 'followers_10k', 'followers_100k', 'followers_1m',
        'likes_1k', 'likes_10k', 'likes_100k',
        'posts_100', 'posts_1k',
        'engagement_rate_10', 'engagement_rate_20',
        'first_month_complete', 'first_year_complete',
        'viral_post', 'verification_badge'
      ]

      major_milestones.include?(milestone_type)
    end

    def self.recent_achievements(account, limit = 10)
      where(social_media_account: account)
        .recent
        .limit(limit)
        .includes(:social_media_post)
    end
  end
end