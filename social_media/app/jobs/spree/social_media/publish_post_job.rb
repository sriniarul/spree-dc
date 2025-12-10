module Spree
  module SocialMedia
    class PublishPostJob < ApplicationJob
      queue_as :default

      retry_on StandardError, wait: :exponentially_longer, attempts: 3

      def perform(social_media_post_id)
        @post = Spree::SocialMediaPost.find(social_media_post_id)
        @account = @post.social_media_account

        Rails.logger.info "Publishing post #{@post.id} to #{@account.platform} account @#{@account.username}"

        return unless @post.may_publish?

        begin
          @post.publish!

          result = case @account.platform
                   when 'instagram'
                     publish_to_instagram
                   when 'facebook'
                     publish_to_facebook
                   when 'youtube'
                     publish_to_youtube
                   when 'tiktok'
                     publish_to_tiktok
                   else
                     raise StandardError, "Unsupported platform: #{@account.platform}"
                   end

          handle_publish_success(result)

        rescue => e
          handle_publish_error(e)
          raise
        end
      end

      private

      def publish_to_instagram
        service = Spree::SocialMedia::InstagramApiService.new(@account)

        # Process and optimize media for Instagram
        media_processor = Spree::SocialMedia::MediaProcessor.new(@post)
        unless media_processor.process_all_media
          raise StandardError, "Media processing failed: #{media_processor.errors.join(', ')}"
        end

        # Optimize for Instagram platform
        unless media_processor.optimize_for_platform('instagram')
          raise StandardError, "Instagram optimization failed: #{media_processor.errors.join(', ')}"
        end

        # Generate thumbnails for videos
        media_processor.generate_thumbnails

        # Use processed media URLs
        media_urls = media_processor.media_urls

        publish_options = {
          content_type: @post.content_type&.to_sym || :feed,
          media_urls: media_urls,
          hashtags: @post.hashtags,
          product_tags: parse_product_tags(@post.product_mentions)
        }

        # Add specific options based on content type
        case @post.content_type
        when 'story'
          publish_options[:link_url] = @post.link_url if @post.link_url.present?
        when 'reel'
          publish_options[:share_to_feed] = true
          publish_options[:cover_url] = @post.thumbnail_url if @post.thumbnail_url.present?
        end

        Rails.logger.info "Publishing Instagram #{@post.content_type} with #{media_urls.size} media files"

        result = service.post(@post.caption, publish_options)

        unless result[:success]
          raise StandardError, "Instagram publish failed: #{result[:error]}"
        end

        {
          platform_post_id: result[:platform_post_id],
          platform_url: result[:platform_url],
          published_at: Time.current
        }
      end

      def publish_to_facebook
        service = Spree::SocialMedia::FacebookApiService.new(@account)

        media_urls = prepare_media_urls(@post.media_attachments)

        publish_options = {
          media_urls: media_urls,
          hashtags: @post.hashtags
        }

        Rails.logger.info "Publishing Facebook post with #{media_urls.size} media files"

        result = service.post(@post.caption, publish_options)

        unless result[:success]
          raise StandardError, "Facebook publish failed: #{result[:error]}"
        end

        {
          platform_post_id: result[:platform_post_id],
          platform_url: result[:platform_url],
          published_at: Time.current
        }
      end

      def publish_to_youtube
        service = Spree::SocialMedia::YouTubeApiService.new(@account)

        video_file = @post.media_attachments.find { |attachment| video_file?(attachment.filename.to_s) }

        unless video_file
          raise StandardError, "YouTube posts require a video file"
        end

        video_url = prepare_media_url(video_file)

        publish_options = {
          title: extract_title_from_caption(@post.caption),
          description: @post.caption,
          tags: parse_hashtags(@post.hashtags),
          privacy: @post.privacy_level || 'public',
          thumbnail_url: @post.thumbnail_url
        }

        Rails.logger.info "Publishing YouTube video: #{publish_options[:title]}"

        result = service.upload_video(video_url, publish_options)

        unless result[:success]
          raise StandardError, "YouTube publish failed: #{result[:error]}"
        end

        {
          platform_post_id: result[:video_id],
          platform_url: "https://www.youtube.com/watch?v=#{result[:video_id]}",
          published_at: Time.current
        }
      end

      def publish_to_tiktok
        service = Spree::SocialMedia::TikTokApiService.new(@account)

        video_file = @post.media_attachments.find { |attachment| video_file?(attachment.filename.to_s) }

        unless video_file
          raise StandardError, "TikTok posts require a video file"
        end

        video_url = prepare_media_url(video_file)

        publish_options = {
          description: @post.caption,
          hashtags: parse_hashtags(@post.hashtags),
          privacy: @post.privacy_level || 'public',
          allow_comments: true,
          allow_duets: true
        }

        Rails.logger.info "Publishing TikTok video"

        result = service.upload_video(video_url, publish_options)

        unless result[:success]
          raise StandardError, "TikTok publish failed: #{result[:error]}"
        end

        {
          platform_post_id: result[:video_id],
          platform_url: result[:share_url],
          published_at: Time.current
        }
      end

      def handle_publish_success(result)
        @post.update!(
          platform_post_id: result[:platform_post_id],
          platform_url: result[:platform_url],
          published_at: result[:published_at],
          status: 'published'
        )

        Rails.logger.info "Post #{@post.id} successfully published to #{@account.platform}"

        # Update account stats
        update_account_stats

        # Schedule analytics sync
        Spree::SocialMedia::SyncPostAnalyticsJob.perform_in(1.hour, @post.id)

        # Send success notification
        send_success_notification
      end

      def handle_publish_error(error)
        error_message = error.message.truncate(500)

        @post.update!(
          status: 'failed',
          error_message: error_message,
          failed_at: Time.current
        )

        Rails.logger.error "Post #{@post.id} publish failed: #{error_message}"

        # Send error notification
        send_error_notification(error_message)
      end

      def prepare_media_urls(attachments)
        return [] unless attachments

        attachments.map do |attachment|
          prepare_media_url(attachment)
        end.compact
      end

      def prepare_media_url(attachment)
        if attachment.respond_to?(:url)
          # Active Storage attachment
          attachment.url
        elsif attachment.respond_to?(:public_url)
          # Custom attachment handler
          attachment.public_url
        else
          # File path or URL
          attachment.to_s
        end
      end

      def parse_product_tags(product_mentions)
        return [] unless product_mentions.present?

        begin
          JSON.parse(product_mentions)
        rescue JSON::ParserError
          []
        end
      end

      def parse_hashtags(hashtags_string)
        return [] unless hashtags_string.present?

        hashtags_string.scan(/#\w+/).map { |tag| tag[1..-1] } # Remove # symbol
      end

      def extract_title_from_caption(caption)
        # Extract first line or first sentence as title
        lines = caption.split("\n")
        first_line = lines.first&.strip

        if first_line && first_line.length <= 100
          first_line
        else
          caption.split('.').first&.strip&.truncate(100) || caption.truncate(100)
        end
      end

      def video_file?(filename)
        filename.match?(/\.(mp4|mov|avi|mkv|webm)$/i)
      end

      def image_file?(filename)
        filename.match?(/\.(jpg|jpeg|png|gif|webp)$/i)
      end

      def update_account_stats
        # Update posts count
        posts_count = @account.social_media_posts.published.count
        @account.update_column(:posts_count, posts_count)

        # Schedule full account sync if needed
        last_sync = @account.last_synced_at
        if last_sync.nil? || last_sync < 1.hour.ago
          Spree::SocialMedia::SyncAccountDetailsJob.perform_later(@account.id)
        end
      end

      def send_success_notification
        # This could send email, push notification, or webhook
        Rails.logger.info "TODO: Send success notification for post #{@post.id}"

        # Example webhook call:
        # if webhook_url = @post.vendor.webhook_url
        #   HTTParty.post(webhook_url, {
        #     body: {
        #       event: 'post_published',
        #       post_id: @post.id,
        #       platform: @account.platform,
        #       platform_url: @post.platform_url
        #     }.to_json,
        #     headers: { 'Content-Type' => 'application/json' }
        #   })
        # end
      end

      def send_error_notification(error_message)
        # This could send error notification to vendor
        Rails.logger.info "TODO: Send error notification for post #{@post.id}: #{error_message}"

        # Example error notification:
        # Spree::SocialMediaNotificationMailer
        #   .publish_failed(@post, error_message)
        #   .deliver_later
      end
    end
  end
end