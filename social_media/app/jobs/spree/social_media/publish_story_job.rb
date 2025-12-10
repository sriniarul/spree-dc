module Spree
  module SocialMedia
    class PublishStoryJob < ApplicationJob
      queue_as :social_media

      retry_on StandardError, wait: :exponentially_longer, attempts: 3

      def perform(social_media_account_id, story_data)
        @account = Spree::SocialMediaAccount.find(social_media_account_id)
        @story_data = story_data.with_indifferent_access

        Rails.logger.info "Publishing Instagram story for account #{@account.username}"

        begin
          # Initialize story service
          story_service = Spree::SocialMedia::InstagramStoryService.new(@account)

          # Publish the story
          result = story_service.publish_story(@story_data)

          if result[:success]
            # Create social media post record
            create_story_record(result)

            # Update account stats
            update_account_stats

            Rails.logger.info "Successfully published Instagram story #{result[:story_id]}"

            # Send success notification if configured
            send_success_notification(result)
          else
            Rails.logger.error "Failed to publish Instagram story: #{result[:errors].join(', ')}"
            send_failure_notification(result[:errors])
            raise StandardError, "Story publication failed: #{result[:errors].join(', ')}"
          end

        rescue => e
          Rails.logger.error "Instagram story job failed: #{e.message}"
          send_failure_notification([e.message])
          raise
        end
      end

      private

      def create_story_record(publish_result)
        @story_post = Spree::SocialMediaPost.create!(
          social_media_account: @account,
          content_type: 'story',
          caption: @story_data[:text_overlay] || '',
          platform_post_id: publish_result[:story_id],
          status: 'published',
          published_at: Time.current,
          scheduled_at: nil,
          metadata: {
            container_id: publish_result[:container_id],
            media_id: publish_result[:media_id],
            stickers: @story_data[:stickers] || [],
            story_type: determine_story_type
          }.to_json
        )

        # Process media attachments if available
        if @story_data[:media].present?
          process_story_media(@story_post)
        end

        @story_post
      end

      def update_account_stats
        @account.increment!(:posts_count)
        @account.touch(:last_post_at)
      end

      def determine_story_type
        if @story_data[:stickers].present?
          sticker_types = @story_data[:stickers].map { |s| s[:sticker_type] }
          if sticker_types.include?('poll')
            'interactive_poll'
          elsif sticker_types.include?('question')
            'interactive_question'
          elsif sticker_types.include?('countdown')
            'interactive_countdown'
          else
            'interactive'
          end
        else
          'standard'
        end
      end

      def process_story_media(story_post)
        media = @story_data[:media]

        if media.is_a?(ActionDispatch::Http::UploadedFile) || media.is_a?(Rack::Test::UploadedFile)
          # Handle uploaded files
          story_post.media_attachments.attach(
            io: media.tempfile,
            filename: media.original_filename,
            content_type: media.content_type
          )
        elsif media.respond_to?(:read)
          # Handle other IO objects
          story_post.media_attachments.attach(
            io: media,
            filename: 'story_media',
            content_type: @story_data[:media_type] == 'IMAGE' ? 'image/jpeg' : 'video/mp4'
          )
        end
      end

      def send_success_notification(result)
        return unless @account.vendor.notification_preferences&.dig('story_published')

        # This could send email, push notification, or webhook
        Rails.logger.info "TODO: Send story published notification for story #{result[:story_id]}"

        # Example webhook call:
        # if webhook_url = @account.vendor.webhook_url
        #   HTTParty.post(webhook_url, {
        #     body: {
        #       event: 'story_published',
        #       story_id: result[:story_id],
        #       account: @account.username,
        #       published_at: Time.current
        #     }.to_json,
        #     headers: { 'Content-Type' => 'application/json' }
        #   })
        # end
      end

      def send_failure_notification(errors)
        return unless @account.vendor.notification_preferences&.dig('story_failed')

        Rails.logger.info "TODO: Send story failed notification - #{errors.join(', ')}"

        # Log failure for admin review
        Rails.logger.error "Story publication failed for account #{@account.username}: #{errors.join(', ')}"
      end
    end
  end
end