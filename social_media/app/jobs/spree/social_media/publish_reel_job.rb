module Spree
  module SocialMedia
    class PublishReelJob < ApplicationJob
      queue_as :social_media

      retry_on StandardError, wait: :exponentially_longer, attempts: 3

      def perform(social_media_account_id, reel_data)
        @account = Spree::SocialMediaAccount.find(social_media_account_id)
        @reel_data = reel_data.with_indifferent_access

        Rails.logger.info "Publishing Instagram reel for account #{@account.username}"

        begin
          # Initialize reel service
          reel_service = Spree::SocialMedia::InstagramReelService.new(@account)

          # Publish the reel
          result = reel_service.publish_reel(@reel_data)

          if result[:success]
            # Create social media post record
            create_reel_record(result)

            # Update account stats
            update_account_stats

            # Schedule analytics sync for later (reels need time to gather data)
            schedule_analytics_sync

            Rails.logger.info "Successfully published Instagram reel #{result[:reel_id]}"

            # Send success notification if configured
            send_success_notification(result)
          else
            Rails.logger.error "Failed to publish Instagram reel: #{result[:errors].join(', ')}"
            send_failure_notification(result[:errors])
            raise StandardError, "Reel publication failed: #{result[:errors].join(', ')}"
          end

        rescue => e
          Rails.logger.error "Instagram reel job failed: #{e.message}"
          send_failure_notification([e.message])
          raise
        end
      end

      private

      def create_reel_record(publish_result)
        @reel_post = Spree::SocialMediaPost.create!(
          social_media_account: @account,
          content_type: 'reel',
          caption: @reel_data[:caption] || '',
          hashtags: extract_hashtags_from_caption,
          platform_post_id: publish_result[:reel_id],
          status: 'published',
          published_at: Time.current,
          scheduled_at: nil,
          metadata: {
            container_id: publish_result[:container_id],
            video_id: publish_result[:video_id],
            audio_name: @reel_data[:audio_name],
            cover_offset: @reel_data[:cover_offset],
            location_id: @reel_data[:location_id],
            reel_length: determine_reel_length,
            optimization_applied: @reel_data[:optimization_applied] || false
          }.to_json
        )

        # Process video attachment
        if @reel_data[:video].present?
          process_reel_video(@reel_post)
        end

        # Process cover image if provided
        if @reel_data[:cover_image].present?
          process_cover_image(@reel_post)
        end

        @reel_post
      end

      def update_account_stats
        @account.increment!(:posts_count)
        @account.touch(:last_post_at)

        # Update reel-specific stats if available
        if @account.metadata.present?
          metadata = JSON.parse(@account.metadata)
          metadata['reels_count'] = (metadata['reels_count'] || 0) + 1
          @account.update!(metadata: metadata.to_json)
        end
      end

      def extract_hashtags_from_caption
        return '' unless @reel_data[:caption].present?

        hashtags = @reel_data[:caption].scan(/#\w+/)
        hashtags.join(' ')
      end

      def determine_reel_length
        # Try to determine video length from metadata or file
        if @reel_data[:video].respond_to?(:blob)
          metadata = @reel_data[:video].blob.metadata || {}
          metadata['duration'] || 'unknown'
        else
          'unknown'
        end
      end

      def process_reel_video(reel_post)
        video = @reel_data[:video]

        if video.is_a?(ActionDispatch::Http::UploadedFile) || video.is_a?(Rack::Test::UploadedFile)
          # Handle uploaded files
          reel_post.media_attachments.attach(
            io: video.tempfile,
            filename: video.original_filename,
            content_type: video.content_type
          )
        elsif video.respond_to?(:read)
          # Handle other IO objects
          reel_post.media_attachments.attach(
            io: video,
            filename: 'reel_video.mp4',
            content_type: 'video/mp4'
          )
        end
      end

      def process_cover_image(reel_post)
        cover = @reel_data[:cover_image]

        if cover.is_a?(ActionDispatch::Http::UploadedFile) || cover.is_a?(Rack::Test::UploadedFile)
          reel_post.media_attachments.attach(
            io: cover.tempfile,
            filename: "cover_#{cover.original_filename}",
            content_type: cover.content_type
          )
        elsif cover.respond_to?(:read)
          reel_post.media_attachments.attach(
            io: cover,
            filename: 'reel_cover.jpg',
            content_type: 'image/jpeg'
          )
        end
      end

      def schedule_analytics_sync
        # Schedule analytics sync for 2 hours later to allow metrics to populate
        Spree::SocialMedia::SyncPostAnalyticsJob.perform_in(
          2.hours,
          @reel_post.id
        )

        # Schedule additional syncs for comprehensive data collection
        [6.hours, 24.hours, 72.hours].each do |delay|
          Spree::SocialMedia::SyncPostAnalyticsJob.perform_in(
            delay,
            @reel_post.id
          )
        end
      end

      def send_success_notification(result)
        return unless @account.vendor.notification_preferences&.dig('reel_published')

        # This could send email, push notification, or webhook
        Rails.logger.info "TODO: Send reel published notification for reel #{result[:reel_id]}"

        # Example implementation:
        # notification_data = {
        #   event: 'reel_published',
        #   reel_id: result[:reel_id],
        #   account: @account.username,
        #   caption: @reel_data[:caption],
        #   published_at: Time.current,
        #   analytics_available_at: 2.hours.from_now
        # }

        # Send webhook if configured
        # if webhook_url = @account.vendor.webhook_url
        #   HTTParty.post(webhook_url, {
        #     body: notification_data.to_json,
        #     headers: { 'Content-Type' => 'application/json' }
        #   })
        # end

        # Send email notification
        # if @account.vendor.email_notifications_enabled?
        #   SocialMediaMailer.reel_published(@account.vendor, notification_data).deliver_later
        # end
      end

      def send_failure_notification(errors)
        return unless @account.vendor.notification_preferences&.dig('reel_failed')

        Rails.logger.info "TODO: Send reel failed notification - #{errors.join(', ')}"

        # Log failure details for debugging
        Rails.logger.error "Reel publication failed for account #{@account.username}: #{errors.join(', ')}"

        error_data = {
          account_id: @account.id,
          account_username: @account.username,
          vendor_id: @account.vendor.id,
          errors: errors,
          reel_data_summary: {
            has_video: @reel_data[:video].present?,
            has_caption: @reel_data[:caption].present?,
            has_audio: @reel_data[:audio_name].present?,
            timestamp: Time.current
          },
          retry_count: executions - 1,
          max_retries: 3
        }

        # Store error for admin review
        Rails.logger.error "Reel job error details: #{error_data.to_json}"

        # Send error notification via configured channels
        # if webhook_url = @account.vendor.webhook_url
        #   HTTParty.post("#{webhook_url}/errors", {
        #     body: { event: 'reel_publication_failed', data: error_data }.to_json,
        #     headers: { 'Content-Type' => 'application/json' }
        #   })
        # rescue => e
        #   Rails.logger.error "Failed to send error webhook: #{e.message}"
        # end
      end
    end
  end
end