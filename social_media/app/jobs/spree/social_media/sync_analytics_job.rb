module Spree
  module SocialMedia
    class SyncAnalyticsJob < ApplicationJob
      queue_as :default

      def perform(account_id, date_range = 30.days)
        account = Spree::SocialMediaAccount.find_by(id: account_id)
        return unless account&.active? && account.analytics_enabled?

        Rails.logger.info "Syncing analytics for #{account.platform} account #{account.id}"

        case account.platform
        when 'facebook'
          sync_facebook_analytics(account, date_range)
        when 'instagram'
          sync_instagram_analytics(account, date_range)
        when 'youtube'
          sync_youtube_analytics(account, date_range)
        when 'tiktok'
          sync_tiktok_analytics(account, date_range)
        when 'whatsapp'
          sync_whatsapp_analytics(account, date_range)
        end

        account.update!(last_sync_at: Time.current)
      rescue => e
        Rails.logger.error "Failed to sync analytics for account #{account_id}: #{e.message}"
        account&.mark_error!("Analytics sync failed: #{e.message}")
        raise e
      end

      private

      def sync_facebook_analytics(account, date_range)
        service = Spree::SocialMedia::FacebookApiService.new(account)

        (date_range.days.ago.to_date..Date.current).each do |date|
          analytics_data = service.get_page_insights(date)

          next unless analytics_data

          analytics = account.social_media_analytics.find_or_create_by(date: date)
          analytics.update!(
            impressions: analytics_data['page_impressions'] || 0,
            likes: analytics_data['page_fans'] || 0,
            comments: analytics_data['page_post_engagements'] || 0,
            shares: analytics_data['page_content_activity'] || 0,
            clicks: analytics_data['page_clicks_total'] || 0
          )
        end
      end

      def sync_instagram_analytics(account, date_range)
        service = Spree::SocialMedia::InstagramApiService.new(account)

        (date_range.days.ago.to_date..Date.current).each do |date|
          analytics_data = service.get_insights(date)

          next unless analytics_data

          analytics = account.social_media_analytics.find_or_create_by(date: date)
          analytics.update!(
            impressions: analytics_data['impressions'] || 0,
            likes: analytics_data['likes'] || 0,
            comments: analytics_data['comments'] || 0,
            shares: analytics_data['shares'] || 0,
            clicks: analytics_data['profile_views'] || 0
          )
        end
      end

      def sync_youtube_analytics(account, date_range)
        service = Spree::SocialMedia::YoutubeApiService.new(account)

        analytics_data = service.get_analytics_report(date_range.days.ago.to_date, Date.current)

        if analytics_data && analytics_data['rows']
          analytics_data['rows'].each do |row|
            date = Date.parse(row[0]) # First column is date

            analytics = account.social_media_analytics.find_or_create_by(date: date)
            analytics.update!(
              impressions: row[1] || 0, # views
              likes: row[2] || 0,
              comments: row[3] || 0,
              shares: row[4] || 0,
              clicks: row[5] || 0 # subscribersGained
            )
          end
        end
      end

      def sync_tiktok_analytics(account, date_range)
        # TikTok analytics implementation would go here
        Rails.logger.info "TikTok analytics sync not yet implemented"
      end

      def sync_whatsapp_analytics(account, date_range)
        # WhatsApp Business analytics implementation would go here
        Rails.logger.info "WhatsApp analytics sync not yet implemented"
      end
    end
  end
end