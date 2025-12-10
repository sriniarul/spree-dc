module Spree
  module SocialMedia
    class DisableAnalyticsSyncJob < ApplicationJob
      queue_as :default

      def perform(account_id)
        account = Spree::SocialMediaAccount.find_by(id: account_id)
        return unless account

        Rails.logger.info "Disabling analytics sync for #{account.platform} account #{account.id}"

        # Disable analytics collection
        account.update!(analytics_enabled: false)

        # Cancel any pending analytics sync jobs for this account
        # Note: This depends on your job queue implementation
        # For Sidekiq, you might use something like:
        # Sidekiq::Cron::Job.destroy("sync_analytics_#{account.id}")

        Rails.logger.info "Analytics sync disabled for account #{account.id}. Remove from your job scheduler if needed."
      rescue => e
        Rails.logger.error "Failed to disable analytics sync for account #{account_id}: #{e.message}"
        raise e
      end
    end
  end
end