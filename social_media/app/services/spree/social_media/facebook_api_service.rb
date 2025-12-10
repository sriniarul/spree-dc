require 'httparty'

module Spree
  module SocialMedia
    class FacebookApiService
      include HTTParty
      base_uri 'https://graph.facebook.com/v18.0'

      def initialize(social_media_account)
        @account = social_media_account
        @access_token = @account.access_token
        @page_id = @account.page_id
      end

      # Test connection to Facebook
      def test_connection
        response = get("/#{@page_id}?fields=id,name,access_token&access_token=#{@access_token}")
        response.success? && response.parsed_response['id'].present?
      rescue => e
        Rails.logger.error "Facebook connection test failed: #{e.message}"
        false
      end

      # Post content to Facebook
      def post(content, options = {})
        begin
          media_urls = options[:media_urls] || []

          if media_urls.empty?
            # Text-only post
            result = create_text_post(content, options)
          elsif media_urls.size == 1
            # Single media post
            if image_file?(media_urls.first)
              result = create_photo_post(content, media_urls.first, options)
            elsif video_file?(media_urls.first)
              result = create_video_post(content, media_urls.first, options)
            else
              result = create_link_post(content, media_urls.first, options)
            end
          else
            # Multiple photos post
            result = create_multiple_photos_post(content, media_urls, options)
          end

          if result[:success]
            {
              success: true,
              platform_post_id: result[:post_id],
              platform_url: "https://www.facebook.com/#{result[:post_id]}"
            }
          else
            { success: false, error: result[:error] }
          end

        rescue => e
          Rails.logger.error "Facebook post failed: #{e.message}"
          { success: false, error: e.message }
        end
      end

      # Get page access token (needed for posting)
      def get_page_access_token
        response = get("/#{@page_id}?fields=access_token&access_token=#{@access_token}")

        if response.success? && response.parsed_response['access_token']
          page_access_token = response.parsed_response['access_token']

          # Update the account with the page access token
          @account.update!(
            access_token: page_access_token,
            token_metadata: (@account.token_metadata || {}).merge(
              page_access_token: page_access_token,
              user_access_token: @access_token
            )
          )

          @access_token = page_access_token
          true
        else
          false
        end
      end

      # Sync account analytics
      def sync_analytics(date_range = 30.days.ago..Date.current)
        begin
          insights = get_page_insights(date_range)

          date_range.each do |date|
            analytics_data = extract_analytics_for_date(insights, date)

            Spree::SocialMediaAnalytics.find_or_create_by(
              social_media_account: @account,
              date: date
            ).update!(analytics_data)
          end

          true
        rescue => e
          Rails.logger.error "Facebook analytics sync failed: #{e.message}"
          false
        end
      end

      # Get connected Instagram business account
      def get_connected_instagram_account
        response = get("/#{@page_id}?fields=instagram_business_account&access_token=#{@access_token}")

        if response.success? && response.parsed_response['instagram_business_account']
          instagram_account_id = response.parsed_response['instagram_business_account']['id']

          # Get Instagram account details
          instagram_response = get("/#{instagram_account_id}?fields=id,username,name,followers_count,media_count&access_token=#{@access_token}")

          if instagram_response.success?
            instagram_response.parsed_response
          else
            nil
          end
        else
          nil
        end
      end

      private

      # Create text-only post
      def create_text_post(message, options = {})
        post_params = {
          message: message,
          access_token: @access_token
        }

        # Add link if provided
        if options[:link_url].present?
          post_params[:link] = options[:link_url]
        end

        response = self.class.post("/#{@page_id}/feed", body: post_params)

        if response.success?
          { success: true, post_id: response.parsed_response['id'] }
        else
          { success: false, error: parse_error(response) }
        end
      end

      # Create photo post
      def create_photo_post(caption, photo_url, options = {})
        post_params = {
          url: photo_url,
          caption: caption,
          access_token: @access_token
        }

        response = self.class.post("/#{@page_id}/photos", body: post_params)

        if response.success?
          { success: true, post_id: response.parsed_response['id'] }
        else
          { success: false, error: parse_error(response) }
        end
      end

      # Create video post
      def create_video_post(description, video_url, options = {})
        post_params = {
          file_url: video_url,
          description: description,
          access_token: @access_token
        }

        # Add video-specific options
        if options[:thumbnail_url].present?
          post_params[:thumb] = options[:thumbnail_url]
        end

        response = self.class.post("/#{@page_id}/videos", body: post_params)

        if response.success?
          { success: true, post_id: response.parsed_response['id'] }
        else
          { success: false, error: parse_error(response) }
        end
      end

      # Create link post
      def create_link_post(message, link_url, options = {})
        post_params = {
          message: message,
          link: link_url,
          access_token: @access_token
        }

        response = self.class.post("/#{@page_id}/feed", body: post_params)

        if response.success?
          { success: true, post_id: response.parsed_response['id'] }
        else
          { success: false, error: parse_error(response) }
        end
      end

      # Create multiple photos post
      def create_multiple_photos_post(caption, photo_urls, options = {})
        # For Facebook, we need to create individual photo objects first, then create a post
        photo_objects = []

        photo_urls.each do |photo_url|
          next unless image_file?(photo_url)

          # Upload photo without posting
          response = self.class.post("/#{@page_id}/photos",
            body: {
              url: photo_url,
              published: false,
              access_token: @access_token
            }
          )

          if response.success?
            photo_objects << { media_fbid: response.parsed_response['id'] }
          else
            Rails.logger.warn "Failed to upload photo #{photo_url}: #{parse_error(response)}"
          end
        end

        return { success: false, error: 'No photos could be uploaded' } if photo_objects.empty?

        # Create the post with multiple photos
        post_params = {
          message: caption,
          attached_media: photo_objects.to_json,
          access_token: @access_token
        }

        response = self.class.post("/#{@page_id}/feed", body: post_params)

        if response.success?
          { success: true, post_id: response.parsed_response['id'] }
        else
          { success: false, error: parse_error(response) }
        end
      end

      # Get page insights for analytics
      def get_page_insights(date_range)
        metrics = %w[
          page_impressions page_impressions_unique page_post_engagements
          page_engaged_users page_fans page_fan_adds page_fan_removes
          page_views_total page_views_unique
        ]

        since_date = date_range.begin.strftime('%Y-%m-%d')
        until_date = date_range.end.strftime('%Y-%m-%d')

        response = self.class.get("/#{@page_id}/insights",
          query: {
            metric: metrics.join(','),
            period: 'day',
            since: since_date,
            until: until_date,
            access_token: @access_token
          }
        )

        if response.success?
          response.parsed_response['data']
        else
          []
        end
      end

      # Extract analytics data for specific date
      def extract_analytics_for_date(insights_data, date)
        date_str = date.strftime('%Y-%m-%d')

        analytics = {
          impressions: 0,
          reach: 0,
          likes: 0,
          comments: 0,
          shares: 0,
          clicks: 0,
          followers_count: 0
        }

        insights_data.each do |insight|
          metric_name = insight['name']
          values = insight['values'] || []

          date_value = values.find { |v| v['end_time']&.start_with?(date_str) }
          next unless date_value

          case metric_name
          when 'page_impressions'
            analytics[:impressions] = date_value['value'] || 0
          when 'page_impressions_unique'
            analytics[:reach] = date_value['value'] || 0
          when 'page_post_engagements'
            analytics[:likes] = date_value['value'] || 0
          when 'page_engaged_users'
            analytics[:comments] = date_value['value'] || 0
          when 'page_fans'
            analytics[:followers_count] = date_value['value'] || 0
          when 'page_views_total'
            analytics[:clicks] = date_value['value'] || 0
          end
        end

        analytics
      end

      # Helper methods
      def image_file?(url)
        url.match?(/\.(jpg|jpeg|png|gif|webp)(\?.*)?$/i)
      end

      def video_file?(url)
        url.match?(/\.(mp4|mov|avi|mkv|webm)(\?.*)?$/i)
      end

      def parse_error(response)
        error_data = response.parsed_response
        if error_data.is_a?(Hash) && error_data['error']
          "#{error_data['error']['message']} (Code: #{error_data['error']['code']})"
        else
          "Facebook API error: #{response.code}"
        end
      end

      def get(path)
        self.class.get(path)
      end
    end
  end
end