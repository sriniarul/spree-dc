require 'httparty'

module Spree
  module SocialMedia
    class InstagramApiService
      include HTTParty
      # Using Instagram Graph API (not Facebook Graph API)
      base_uri 'https://graph.instagram.com'

      def initialize(social_media_account)
        @account = social_media_account
        @access_token = @account.access_token
        @instagram_user_id = @account.platform_user_id
      end

      # Test connection to Instagram
      def test_connection
        response = get("/me?fields=id,username,account_type&access_token=#{@access_token}")
        response.success? && response.parsed_response['id'].present?
      rescue => e
        Rails.logger.error "Instagram connection test failed: #{e.message}"
        false
      end

      def get_profile_info
        fields = %w[
          id
          username
          name
          account_type
          media_count
          followers_count
          follows_count
          biography
          website
          profile_picture_url
        ].join(',')

        response = get("/me?fields=#{fields}&access_token=#{@access_token}")

        if response.success?
          response.parsed_response
        else
          Rails.logger.error "Failed to get Instagram profile info: #{parse_error(response)}"
          nil
        end
      rescue => e
        Rails.logger.error "Instagram profile fetch failed: #{e.message}"
        nil
      end

      # Post content to Instagram
      def post(content, options = {})
        case options[:content_type]&.to_sym
        when :feed
          post_feed(content, options)
        when :story
          post_story(content, options)
        when :reel
          post_reel(content, options)
        else
          post_feed(content, options) # Default to feed post
        end
      end

      # Post to Instagram Feed
      def post_feed(content, options = {})
        media_urls = options[:media_urls] || []

        if media_urls.empty?
          return { success: false, error: 'Instagram posts require at least one image or video' }
        end

        begin
          if media_urls.size == 1
            # Single media post
            result = create_single_media_post(content, media_urls.first, options)
          else
            # Carousel post (multiple media)
            result = create_carousel_post(content, media_urls, options)
          end

          if result[:success]
            {
              success: true,
              platform_post_id: result[:post_id],
              platform_url: "https://www.instagram.com/p/#{result[:post_id]}/"
            }
          else
            { success: false, error: result[:error] }
          end

        rescue => e
          Rails.logger.error "Instagram feed post failed: #{e.message}"
          { success: false, error: e.message }
        end
      end

      # Post Instagram Story
      def post_story(content, options = {})
        media_url = options[:media_urls]&.first

        unless media_url
          return { success: false, error: 'Instagram stories require an image or video' }
        end

        begin
          # Step 1: Upload media for story
          container_response = create_story_container(media_url, content, options)

          unless container_response[:success]
            return { success: false, error: container_response[:error] }
          end

          # Step 2: Publish the story
          publish_response = publish_story(container_response[:container_id])

          if publish_response[:success]
            {
              success: true,
              platform_post_id: publish_response[:story_id],
              platform_url: "https://www.instagram.com/stories/#{@account.username}/"
            }
          else
            { success: false, error: publish_response[:error] }
          end

        rescue => e
          Rails.logger.error "Instagram story post failed: #{e.message}"
          { success: false, error: e.message }
        end
      end

      # Post Instagram Reel
      def post_reel(content, options = {})
        video_url = options[:media_urls]&.first

        unless video_url && video_file?(video_url)
          return { success: false, error: 'Instagram reels require a video file' }
        end

        begin
          # Step 1: Create media container for reel
          container_response = create_reel_container(video_url, content, options)

          unless container_response[:success]
            return { success: false, error: container_response[:error] }
          end

          # Step 2: Publish the reel
          publish_response = publish_reel(container_response[:container_id])

          if publish_response[:success]
            {
              success: true,
              platform_post_id: publish_response[:reel_id],
              platform_url: "https://www.instagram.com/reel/#{publish_response[:reel_id]}/"
            }
          else
            { success: false, error: publish_response[:error] }
          end

        rescue => e
          Rails.logger.error "Instagram reel post failed: #{e.message}"
          { success: false, error: e.message }
        end
      end

      # Sync account analytics
      def sync_analytics(date_range = 30.days.ago..Date.current)
        begin
          insights = get_account_insights(date_range)

          date_range.each do |date|
            analytics_data = extract_analytics_for_date(insights, date)

            Spree::SocialMediaAnalytics.find_or_create_by(
              social_media_account: @account,
              date: date
            ).update!(analytics_data)
          end

          true
        rescue => e
          Rails.logger.error "Instagram analytics sync failed: #{e.message}"
          false
        end
      end

      private

      # Create single media post
      def create_single_media_post(caption, media_url, options = {})
        media_type = image_file?(media_url) ? 'IMAGE' : 'VIDEO'

        # Step 1: Create media container
        # Using Instagram Graph API endpoint (not Facebook Graph API)
        # NOTE: access_token must be sent as query parameter, not in body!
        container_params = {
          image_url: media_type == 'IMAGE' ? media_url : nil,
          video_url: media_type == 'VIDEO' ? media_url : nil,
          media_type: media_type,
          caption: caption
        }.compact

        # Add product tags if provided
        if options[:product_tags].present?
          container_params[:product_tags] = options[:product_tags].to_json
        end

        # Debug logging
        Rails.logger.info "=" * 80
        Rails.logger.info "Instagram API: Creating media container"
        Rails.logger.info "Media URL: #{media_url}"
        Rails.logger.info "Media Type: #{media_type}"
        Rails.logger.info "Caption length: #{caption.length} chars"
        Rails.logger.info "Access Token (first 10 chars): #{@access_token[0..9]}..."
        Rails.logger.info "=" * 80

        # Use /me endpoint for current authenticated user
        # Access token MUST be in query string, not body
        # Use form-encoded body for the parameters
        container_response = self.class.post(
          "/me/media",
          query: { access_token: @access_token },
          body: container_params,
          headers: { 'Content-Type' => 'application/x-www-form-urlencoded' }
        )

        Rails.logger.info "Container Response Code: #{container_response.code}"
        Rails.logger.info "Container Response Body: #{container_response.body}"
        Rails.logger.info "=" * 80

        unless container_response.success?
          error_msg = parse_error(container_response)
          Rails.logger.error "Container creation failed: #{error_msg}"
          return { success: false, error: error_msg }
        end

        container_id = container_response.parsed_response['id']
        Rails.logger.info "Container created successfully: #{container_id}"

        # Step 2: Publish the post
        Rails.logger.info "Publishing container: #{container_id}"
        # Access token MUST be in query string, not body
        publish_response = self.class.post(
          "/me/media_publish",
          query: { access_token: @access_token },
          body: { creation_id: container_id },
          headers: { 'Content-Type' => 'application/x-www-form-urlencoded' }
        )

        Rails.logger.info "Publish Response Code: #{publish_response.code}"
        Rails.logger.info "Publish Response Body: #{publish_response.body}"
        Rails.logger.info "=" * 80

        if publish_response.success?
          { success: true, post_id: publish_response.parsed_response['id'] }
        else
          error_msg = parse_error(publish_response)
          Rails.logger.error "Publish failed: #{error_msg}"
          { success: false, error: error_msg }
        end
      end

      # Create carousel post (multiple media)
      def create_carousel_post(caption, media_urls, options = {})
        container_ids = []

        # Step 1: Create media containers for each item
        media_urls.each do |media_url|
          media_type = image_file?(media_url) ? 'IMAGE' : 'VIDEO'

          container_params = {
            image_url: media_type == 'IMAGE' ? media_url : nil,
            video_url: media_type == 'VIDEO' ? media_url : nil,
            media_type: media_type,
            is_carousel_item: true
          }.compact

          # Access token MUST be in query string, not body
          response = self.class.post(
            "/me/media",
            query: { access_token: @access_token },
            body: container_params,
            headers: { 'Content-Type' => 'application/x-www-form-urlencoded' }
          )

          unless response.success?
            return { success: false, error: parse_error(response) }
          end

          container_ids << response.parsed_response['id']
        end

        # Step 2: Create carousel container
        carousel_params = {
          media_type: 'CAROUSEL',
          children: container_ids.join(','),
          caption: caption
        }

        # Access token MUST be in query string, not body
        carousel_response = self.class.post(
          "/me/media",
          query: { access_token: @access_token },
          body: carousel_params,
          headers: { 'Content-Type' => 'application/x-www-form-urlencoded' }
        )

        unless carousel_response.success?
          return { success: false, error: parse_error(carousel_response) }
        end

        carousel_id = carousel_response.parsed_response['id']

        # Step 3: Publish the carousel
        # Access token MUST be in query string, not body
        publish_response = self.class.post(
          "/me/media_publish",
          query: { access_token: @access_token },
          body: { creation_id: carousel_id },
          headers: { 'Content-Type' => 'application/x-www-form-urlencoded' }
        )

        if publish_response.success?
          { success: true, post_id: publish_response.parsed_response['id'] }
        else
          { success: false, error: parse_error(publish_response) }
        end
      end

      # Create story container
      # According to Instagram API docs, for stories:
      # - Set media_type to STORIES (not IMAGE or VIDEO)
      # - Use image_url or video_url based on media type
      def create_story_container(media_url, content, options = {})
        is_image = image_file?(media_url)

        # For stories, media_type is always 'STORIES'
        story_params = {
          media_type: 'STORIES'
        }

        # Add image_url or video_url based on media type
        if is_image
          story_params[:image_url] = media_url
        else
          story_params[:video_url] = media_url
        end

        Rails.logger.info "Creating Instagram Story container with #{is_image ? 'image' : 'video'}: #{media_url}"

        # Access token MUST be in query string, not body
        response = self.class.post(
          "/me/media",
          query: { access_token: @access_token },
          body: story_params,
          headers: { 'Content-Type' => 'application/x-www-form-urlencoded' }
        )

        Rails.logger.info "Story container response: #{response.code} - #{response.body}"

        if response.success?
          { success: true, container_id: response.parsed_response['id'] }
        else
          { success: false, error: parse_error(response) }
        end
      end

      # Publish story
      def publish_story(container_id)
        # Access token MUST be in query string, not body
        response = self.class.post(
          "/me/media_publish",
          query: { access_token: @access_token },
          body: { creation_id: container_id },
          headers: { 'Content-Type' => 'application/x-www-form-urlencoded' }
        )

        if response.success?
          { success: true, story_id: response.parsed_response['id'] }
        else
          { success: false, error: parse_error(response) }
        end
      end

      # Create reel container
      def create_reel_container(video_url, caption, options = {})
        reel_params = {
          video_url: video_url,
          media_type: 'REELS',
          caption: caption,
          share_to_feed: options[:share_to_feed] || true
        }

        # Add reel-specific options
        if options[:cover_url].present?
          reel_params[:thumb_offset] = options[:thumb_offset] || 0
        end

        # Access token MUST be in query string, not body
        response = self.class.post(
          "/me/media",
          query: { access_token: @access_token },
          body: reel_params,
          headers: { 'Content-Type' => 'application/x-www-form-urlencoded' }
        )

        if response.success?
          { success: true, container_id: response.parsed_response['id'] }
        else
          { success: false, error: parse_error(response) }
        end
      end

      # Publish reel
      def publish_reel(container_id)
        # Access token MUST be in query string, not body
        response = self.class.post(
          "/me/media_publish",
          query: { access_token: @access_token },
          body: { creation_id: container_id },
          headers: { 'Content-Type' => 'application/x-www-form-urlencoded' }
        )

        if response.success?
          { success: true, reel_id: response.parsed_response['id'] }
        else
          { success: false, error: parse_error(response) }
        end
      end

      # Get account insights for analytics
      # Note: Insights may have limited access with Instagram Login
      # Full insights require instagram_business_manage_insights permission
      def get_account_insights(date_range)
        metrics = %w[impressions reach profile_views]
        period = 'day'

        since_timestamp = date_range.begin.to_time.to_i
        until_timestamp = date_range.end.to_time.to_i

        response = self.class.get("/me/insights",
          query: {
            metric: metrics.join(','),
            period: period,
            since: since_timestamp,
            until: until_timestamp,
            access_token: @access_token
          }
        )

        if response.success?
          response.parsed_response['data']
        else
          Rails.logger.warn "Failed to get Instagram insights: #{parse_error(response)}"
          []
        end
      end

      # Extract analytics data for specific date
      def extract_analytics_for_date(insights_data, date)
        date_str = date.strftime('%Y-%m-%d')

        analytics = {
          impressions: 0,
          reach: 0,
          profile_views: 0,
          website_clicks: 0
        }

        insights_data.each do |insight|
          metric_name = insight['name']
          values = insight['values'] || []

          date_value = values.find { |v| v['end_time']&.start_with?(date_str) }
          next unless date_value

          case metric_name
          when 'impressions'
            analytics[:impressions] = date_value['value'] || 0
          when 'reach'
            analytics[:reach] = date_value['value'] || 0
          when 'profile_views'
            analytics[:profile_views] = date_value['value'] || 0
          when 'website_clicks'
            analytics[:website_clicks] = date_value['value'] || 0
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
          "Instagram API error: #{response.code}"
        end
      end

      def get(path)
        self.class.get(path)
      end
    end
  end
end