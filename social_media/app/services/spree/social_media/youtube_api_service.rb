require 'httparty'

module Spree
  module SocialMedia
    class YoutubeApiService
      include HTTParty
      base_uri 'https://www.googleapis.com/youtube/v3'

      def initialize(social_media_account)
        @account = social_media_account
        @access_token = social_media_account.access_token
      end

      def test_connection
        response = self.class.get('/channels',
          query: {
            part: 'snippet',
            mine: true,
            access_token: @access_token
          }
        )

        response.success? && response.parsed_response['items']&.any?
      rescue => e
        Rails.logger.error "YouTube connection test failed: #{e.message}"
        false
      end

      def get_channel_info
        response = self.class.get('/channels',
          query: {
            part: 'snippet,statistics,brandingSettings',
            mine: true,
            access_token: @access_token
          }
        )

        if response.success? && response.parsed_response['items']&.any?
          response.parsed_response['items'].first
        else
          Rails.logger.error "Failed to get YouTube channel info: #{response.parsed_response}"
          nil
        end
      rescue => e
        Rails.logger.error "YouTube API error: #{e.message}"
        nil
      end

      def get_analytics_report(start_date, end_date)
        response = self.class.get('/reports',
          query: {
            dimensions: 'day',
            endDate: end_date.strftime('%Y-%m-%d'),
            ids: "channel==#{@account.platform_user_id}",
            metrics: 'views,likes,comments,shares,subscribersGained',
            startDate: start_date.strftime('%Y-%m-%d'),
            access_token: @access_token
          }
        )

        if response.success?
          response.parsed_response
        else
          Rails.logger.error "Failed to get YouTube analytics: #{response.parsed_response}"
          nil
        end
      rescue => e
        Rails.logger.error "YouTube analytics API error: #{e.message}"
        nil
      end

      def upload_video(video_path, title, description, tags = [])
        # This would implement YouTube video upload
        # For now, return a placeholder response
        Rails.logger.info "YouTube video upload not yet implemented"
        { success: false, error: 'Upload not implemented' }
      end

      def get_videos(max_results = 25)
        response = self.class.get('/search',
          query: {
            part: 'snippet',
            channelId: @account.platform_user_id,
            maxResults: max_results,
            order: 'date',
            type: 'video',
            access_token: @access_token
          }
        )

        if response.success?
          response.parsed_response['items'] || []
        else
          Rails.logger.error "Failed to get YouTube videos: #{response.parsed_response}"
          []
        end
      rescue => e
        Rails.logger.error "YouTube videos API error: #{e.message}"
        []
      end

      def refresh_access_token!
        refresh_token = @account.refresh_token
        return false unless refresh_token

        client_id = Rails.application.credentials.dig(:google, :client_id) || ENV['GOOGLE_CLIENT_ID']
        client_secret = Rails.application.credentials.dig(:google, :client_secret) || ENV['GOOGLE_CLIENT_SECRET']

        response = HTTParty.post('https://oauth2.googleapis.com/token',
          body: {
            client_id: client_id,
            client_secret: client_secret,
            refresh_token: refresh_token,
            grant_type: 'refresh_token'
          },
          headers: { 'Content-Type' => 'application/x-www-form-urlencoded' }
        )

        if response.success?
          token_data = response.parsed_response
          @account.update!(
            access_token: token_data['access_token'],
            expires_at: Time.current + token_data['expires_in'].seconds
          )
          @access_token = token_data['access_token']
          true
        else
          Rails.logger.error "Failed to refresh YouTube access token: #{response.parsed_response}"
          false
        end
      rescue => e
        Rails.logger.error "YouTube token refresh error: #{e.message}"
        false
      end

      private

      def headers
        {
          'Authorization' => "Bearer #{@access_token}",
          'Content-Type' => 'application/json'
        }
      end
    end
  end
end