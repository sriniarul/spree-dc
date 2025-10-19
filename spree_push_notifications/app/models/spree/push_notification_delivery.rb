module Spree
  class PushNotificationDelivery < Spree.base_class
    belongs_to :push_notification_campaign, class_name: 'Spree::PushNotificationCampaign'
    belongs_to :push_subscription, class_name: 'Spree::PushSubscription'

    validates :status, presence: true
    validates :delivered_at, presence: true

    enum status: {
      pending: 'pending',
      delivered: 'delivered',
      failed: 'failed',
      clicked: 'clicked',
      dismissed: 'dismissed'
    }

    scope :successful, -> { where(status: 'delivered') }
    scope :failed, -> { where(status: 'failed') }
    scope :clicked, -> { where(status: 'clicked') }
    scope :for_date_range, ->(start_date, end_date) { where(delivered_at: start_date..end_date) }

    def mark_as_clicked!
      update!(status: 'clicked', clicked_at: Time.current)
      push_notification_campaign.increment!(:total_clicked)
    end

    def mark_as_dismissed!
      update!(status: 'dismissed', dismissed_at: Time.current)
    end
  end
end