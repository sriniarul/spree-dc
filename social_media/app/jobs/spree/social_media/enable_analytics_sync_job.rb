module Spree
  module SocialMedia
    class EnableAnalyticsSyncJob < ApplicationJob
      queue_as :default

      def perform(account_id)
        account = Spree::SocialMediaAccount.find_by(id: account_id)
        return unless account&.active?

        Rails.logger.info "Enabling analytics sync for #{account.platform} account #{account.id}"

        # Enable analytics collection if not already enabled
        account.update!(analytics_enabled: true) unless account.analytics_enabled?

        # Schedule initial analytics sync for the past 30 days
        SyncAnalyticsJob.perform_later(account.id, 30.days)

        # Set up recurring analytics sync (this could be done via a cron job or scheduled job)
        # For now, we'll just log that it should be scheduled
        Rails.logger.info "Analytics sync enabled for account #{account.id}. Set up recurring sync in your job scheduler."
      rescue => e
        Rails.logger.error "Failed to enable analytics sync for account #{account_id}: #{e.message}"
        raise e
      end
    end
  end
end