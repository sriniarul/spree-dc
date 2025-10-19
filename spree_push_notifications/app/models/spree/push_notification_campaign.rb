module Spree
  class PushNotificationCampaign < Spree.base_class
    has_many :push_notification_deliveries, class_name: 'Spree::PushNotificationDelivery', dependent: :destroy

    validates :title, presence: true
    validates :body, presence: true
    validates :sent_at, presence: true

    scope :recent, -> { order(sent_at: :desc) }
    scope :for_date_range, ->(start_date, end_date) { where(sent_at: start_date..end_date) }
    scope :this_week, -> { where(sent_at: 7.days.ago..Time.current) }

    def success_rate
      return 0.0 if total_sent == 0
      (total_delivered.to_f / total_sent * 100).round(2)
    end

    def failure_rate
      return 0.0 if total_sent == 0
      (total_failed.to_f / total_sent * 100).round(2)
    end

    def click_rate
      return 0.0 if total_delivered == 0
      (total_clicked.to_f / total_delivered * 100).round(2)
    end

    # Class method for daily stats - optimized to avoid N+1 queries
    def self.daily_stats(days: 7)
      end_date = Date.current.end_of_day
      start_date = (days - 1).days.ago.beginning_of_day

      # Single query to get all campaign data grouped by date
      campaign_stats = where(sent_at: start_date..end_date)
                      .group("DATE(sent_at)")
                      .select([
                        "DATE(sent_at) as date",
                        "COUNT(*) as campaigns_count",
                        "SUM(total_sent) as total_sent",
                        "SUM(total_delivered) as total_delivered",
                        "SUM(total_failed) as total_failed",
                        "SUM(total_clicked) as total_clicked"
                      ])

      # Convert to hash with calculated rates
      stats_hash = {}
      campaign_stats.each do |stat|
        date_str = stat.date.strftime('%Y-%m-%d')
        total_sent = stat.total_sent || 0
        total_delivered = stat.total_delivered || 0
        total_clicked = stat.total_clicked || 0

        stats_hash[date_str] = {
          date: stat.date.to_date,
          campaigns_count: stat.campaigns_count,
          total_sent: total_sent,
          total_delivered: total_delivered,
          total_failed: stat.total_failed || 0,
          total_clicked: total_clicked,
          success_rate: total_sent > 0 ? (total_delivered.to_f / total_sent * 100).round(2) : 0,
          click_rate: total_delivered > 0 ? (total_clicked.to_f / total_delivered * 100).round(2) : 0
        }
      end

      # Ensure we have entries for all days, even with zero data
      days.times do |i|
        date = i.days.ago.to_date
        date_str = date.strftime('%Y-%m-%d')
        unless stats_hash.key?(date_str)
          stats_hash[date_str] = {
            date: date,
            campaigns_count: 0,
            total_sent: 0,
            total_delivered: 0,
            total_failed: 0,
            total_clicked: 0,
            success_rate: 0,
            click_rate: 0
          }
        end
      end

      # Sort by date descending
      stats_hash.sort.reverse.to_h
    end
  end
end