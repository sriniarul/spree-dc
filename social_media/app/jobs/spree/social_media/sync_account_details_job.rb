module Spree
  module SocialMedia
    class SyncAccountDetailsJob < ApplicationJob
      queue_as :default

      def perform(account_id)
        account = Spree::SocialMediaAccount.find_by(id: account_id)
        return unless account&.active?

        Rails.logger.info "Syncing account details for #{account.platform} account #{account.id}"

        case account.platform
        when 'facebook'
          sync_facebook_details(account)
        when 'instagram'
          sync_instagram_details(account)
        when 'youtube'
          sync_youtube_details(account)
        when 'tiktok'
          sync_tiktok_details(account)
        when 'whatsapp'
          sync_whatsapp_details(account)
        end

        account.update!(last_sync_at: Time.current)
      rescue => e
        Rails.logger.error "Failed to sync account details for account #{account_id}: #{e.message}"
        account&.mark_error!("Sync failed: #{e.message}")
        raise e
      end

      private

      def sync_facebook_details(account)
        service = Spree::SocialMedia::FacebookApiService.new(account)
        page_data = service.get_page_info

        if page_data
          account.update!(
            username: page_data['username'] || page_data['name'],
            display_name: page_data['name'],
            bio: page_data['about'],
            followers_count: page_data['fan_count'] || 0,
            profile_image_url: page_data['picture']&.dig('data', 'url'),
            website_url: page_data['website']
          )
        end
      end

      def sync_instagram_details(account)
        service = Spree::SocialMedia::InstagramApiService.new(account)
        profile_data = service.get_profile_info

        if profile_data
          account.update!(
            username: profile_data['username'],
            display_name: profile_data['name'],
            bio: profile_data['biography'],
            followers_count: profile_data['followers_count'] || 0,
            following_count: profile_data['follows_count'] || 0,
            posts_count: profile_data['media_count'] || 0,
            profile_image_url: profile_data['profile_picture_url'],
            website_url: profile_data['website']
          )
        end
      end

      def sync_youtube_details(account)
        service = Spree::SocialMedia::YoutubeApiService.new(account)
        channel_data = service.get_channel_info

        if channel_data
          snippet = channel_data['snippet']
          statistics = channel_data['statistics']

          account.update!(
            username: snippet['title'],
            display_name: snippet['title'],
            bio: snippet['description'],
            followers_count: statistics['subscriberCount'] || 0,
            posts_count: statistics['videoCount'] || 0,
            profile_image_url: snippet.dig('thumbnails', 'high', 'url'),
            website_url: snippet['customUrl'] ? "https://www.youtube.com/#{snippet['customUrl']}" : nil
          )
        end
      end

      def sync_tiktok_details(account)
        # TikTok API implementation would go here
        Rails.logger.info "TikTok account sync not yet implemented"
      end

      def sync_whatsapp_details(account)
        # WhatsApp Business API implementation would go here
        Rails.logger.info "WhatsApp account sync not yet implemented"
      end
    end
  end
end