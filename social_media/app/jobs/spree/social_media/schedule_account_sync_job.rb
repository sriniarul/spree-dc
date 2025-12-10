module Spree
  module SocialMedia
    class ScheduleAccountSyncJob < ApplicationJob
      queue_as :social_media_scheduling

      # This job runs periodically to schedule syncing of all active Instagram accounts
      def perform
        Rails.logger.info "Starting scheduled sync for all active Instagram accounts"

        active_accounts = Spree::SocialMediaAccount
                           .active
                           .where(platform: 'instagram')
                           .where.not(access_token: nil)

        Rails.logger.info "Found #{active_accounts.count} active Instagram accounts to sync"

        sync_count = 0
        error_count = 0

        active_accounts.find_each do |account|
          begin
            # Check if account needs syncing based on sync frequency settings
            if should_sync_account?(account)
              Rails.logger.info "Scheduling sync for account: #{account.username}"

              # Queue the sync job with some delay to avoid API rate limits
              Spree::SocialMedia::SyncInstagramAccountJob.perform_later(account.id)
              sync_count += 1

              # Add a small delay to prevent hitting rate limits
              sleep(0.5) if sync_count % 10 == 0
            else
              Rails.logger.debug "Skipping sync for #{account.username} - not due for sync"
            end
          rescue => e
            Rails.logger.error "Failed to schedule sync for account #{account.id}: #{e.message}"
            error_count += 1
          end
        end

        Rails.logger.info "Scheduled sync jobs completed: #{sync_count} accounts queued, #{error_count} errors"

        # Schedule analytics sync for posts that need updating
        schedule_analytics_sync

        # Clean up old webhook events
        cleanup_old_data
      end

      private

      def should_sync_account?(account)
        # Get sync frequency from vendor settings (default every 4 hours)
        sync_settings = account.vendor.social_media_sync_settings || {}
        sync_frequency_hours = sync_settings.fetch('sync_frequency_hours', 4)

        # Check if enough time has passed since last sync
        last_sync = account.last_synced_at
        return true if last_sync.nil?

        time_since_sync = Time.current - last_sync
        required_interval = sync_frequency_hours.hours

        time_since_sync >= required_interval
      end

      def schedule_analytics_sync
        Rails.logger.info "Scheduling analytics sync for recent posts"

        # Sync analytics for posts published in the last 7 days
        recent_posts = Spree::SocialMediaPost
                        .joins(:social_media_account)
                        .where(spree_social_media_accounts: { platform: 'instagram' })
                        .where('published_at > ?', 7.days.ago)
                        .where('analytics_synced_at IS NULL OR analytics_synced_at < ?', 1.day.ago)

        analytics_count = 0

        recent_posts.find_each do |post|
          begin
            # Queue analytics sync job
            Spree::SocialMedia::SyncPostAnalyticsJob.perform_later(post.id)
            analytics_count += 1

            # Rate limit protection
            sleep(0.2) if analytics_count % 20 == 0
          rescue => e
            Rails.logger.error "Failed to schedule analytics sync for post #{post.id}: #{e.message}"
          end
        end

        Rails.logger.info "Scheduled analytics sync for #{analytics_count} posts"
      end

      def cleanup_old_data
        Rails.logger.info "Starting cleanup of old social media data"

        begin
          # Clean up old webhook events (keep for 90 days)
          deleted_webhooks = Spree::SocialMediaWebhookEvent.cleanup_old_events(90)
          Rails.logger.info "Cleaned up #{deleted_webhooks} old webhook events"

          # Clean up old engagement events (keep for 180 days)
          old_engagement_events = Spree::SocialMediaEngagementEvent
                                   .where('occurred_at < ?', 180.days.ago)
                                   .delete_all
          Rails.logger.info "Cleaned up #{old_engagement_events} old engagement events"

          # Clean up old analytics data (keep for 1 year)
          old_analytics = Spree::SocialMediaAnalytic
                           .where('date < ?', 1.year.ago)
                           .delete_all
          Rails.logger.info "Cleaned up #{old_analytics} old analytics records"

        rescue => e
          Rails.logger.error "Error during cleanup: #{e.message}"
        end
      end
    end
  end
end