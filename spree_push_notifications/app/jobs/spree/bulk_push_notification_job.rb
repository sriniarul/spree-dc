module Spree
  class BulkPushNotificationJob < ApplicationJob
    queue_as :default

    def perform(title, message, options = {})
      Rails.logger.info "Starting bulk push notification: #{title}"

      # Get all active push subscriptions
      subscriptions = Spree::PushSubscription.where('last_used_at > ?', 30.days.ago)

      success_count = 0
      failure_count = 0

      subscriptions.find_each(batch_size: 100) do |subscription|
        result = PushNotificationService.send_to_subscription(
          subscription,
          title,
          message,
          options
        )

        if result[:success] > 0
          success_count += 1
        else
          failure_count += 1
          Rails.logger.warn "Failed to send notification to subscription #{subscription.id}: #{result[:errors]}"
        end
      end

      Rails.logger.info "Bulk push notification completed: #{success_count} success, #{failure_count} failures"

      # Return summary for potential logging or admin feedback
      {
        total_sent: success_count,
        total_failed: failure_count,
        total_subscriptions: subscriptions.count
      }
    end
  end
end