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

    # Class method for daily stats
    def self.daily_stats(days: 7)
      stats = {}
      days.times do |i|
        date = i.days.ago.to_date
        campaigns = where(sent_at: date.beginning_of_day..date.end_of_day)

        stats[date.strftime('%Y-%m-%d')] = {
          date: date,
          campaigns_count: campaigns.count,
          total_sent: campaigns.sum(:total_sent),
          total_delivered: campaigns.sum(:total_delivered),
          total_failed: campaigns.sum(:total_failed),
          total_clicked: campaigns.sum(:total_clicked),
          success_rate: campaigns.count > 0 ? (campaigns.sum(:total_delivered).to_f / campaigns.sum(:total_sent) * 100).round(2) : 0,
          click_rate: campaigns.sum(:total_delivered) > 0 ? (campaigns.sum(:total_clicked).to_f / campaigns.sum(:total_delivered) * 100).round(2) : 0
        }
      end

      stats.sort.reverse.to_h
    end
  end
end