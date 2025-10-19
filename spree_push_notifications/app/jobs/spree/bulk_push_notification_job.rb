module Spree
  class BulkPushNotificationJob < ApplicationJob
    queue_as :default

    def perform(title, message, options = {})
      Rails.logger.info "Starting bulk push notification: #{title}"

      # Get all active push subscriptions
      subscriptions = Spree::PushSubscription.where('last_used_at > ?', 30.days.ago)

      if subscriptions.empty?
        Rails.logger.info "No active subscriptions found for bulk notification"
        return { total_sent: 0, total_failed: 0, total_subscriptions: 0, campaign_id: nil }
      end

      # Use the updated service method that handles campaign tracking automatically
      result = PushNotificationService.send_to_subscriptions(
        subscriptions,
        title,
        message,
        options
      )

      campaign = result[:campaign]
      Rails.logger.info "Bulk push notification completed: #{result[:success]} success, #{result[:failure]} failures (Campaign ID: #{campaign&.id})"

      # Return summary for potential logging or admin feedback
      {
        total_sent: result[:success],
        total_failed: result[:failure],
        total_subscriptions: subscriptions.count,
        campaign_id: campaign&.id,
        errors: result[:errors]
      }
    end
  end
end