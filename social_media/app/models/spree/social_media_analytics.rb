module Spree
  class SocialMediaAnalytics < Spree.base_class
    acts_as_paranoid

    belongs_to :social_media_account, class_name: 'Spree::SocialMediaAccount'

    validates :date, presence: true
    validates :impressions, :likes, :comments, :shares, :clicks, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :social_media_account_id, presence: true

    scope :for_date_range, ->(start_date, end_date) { where(date: start_date..end_date) }
    scope :recent, -> { where(date: 30.days.ago..Date.current) }

    def total_engagement
      likes + comments + shares + clicks
    end

    def engagement_rate
      return 0 if impressions.zero?
      (total_engagement.to_f / impressions * 100).round(2)
    end
  end
end