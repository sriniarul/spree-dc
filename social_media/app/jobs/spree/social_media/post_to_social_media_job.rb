module Spree
  module SocialMedia
    class PostToSocialMediaJob < ApplicationJob
      queue_as :social_media

      retry_on StandardError, wait: :exponentially_longer, attempts: 3

      def perform(social_media_post_id)
        post = Spree::SocialMediaPost.find(social_media_post_id)
        account = post.social_media_account

        return unless post.scheduled? || post.draft?
        return unless account.active? && account.access_token_valid?

        begin
          # Get the appropriate service class for the platform
          service_class = "Spree::SocialMedia::#{account.platform.camelize}PostService".constantize
          service = service_class.new(account)

          # Prepare the post content and options
          content = post.content
          options = prepare_post_options(post)

          # Post to the social media platform
          result = service.post(content, options)

          if result[:success]
            # Mark the post as successfully posted
            post.mark_posted!(result[:platform_post_id], result[:platform_url])

            # Schedule analytics collection for later
            Spree::SocialMedia::CollectPostAnalyticsJob.perform_in(1.hour, post.id)

            Rails.logger.info "Successfully posted to #{account.platform} for vendor #{account.vendor.name}"
          else
            # Mark the post as failed
            post.mark_failed!(result[:error] || 'Unknown error occurred')
            Rails.logger.error "Failed to post to #{account.platform}: #{result[:error]}"
          end

        rescue => e
          # Handle any unexpected errors
          post.mark_failed!(e.message)
          Rails.logger.error "Error posting to #{account.platform}: #{e.message}"
          Rails.error.report(e, context: {
            post_id: post.id,
            account_id: account.id,
            platform: account.platform
          })
          raise e
        end
      end

      private

      def prepare_post_options(post)
        options = {
          media_urls: post.media_urls || [],
          hashtags: post.hashtags || [],
          product_id: post.product_id
        }

        # Add platform-specific options
        case post.social_media_account.platform
        when 'facebook'
          options.merge!(prepare_facebook_options(post))
        when 'instagram'
          options.merge!(prepare_instagram_options(post))
        when 'youtube'
          options.merge!(prepare_youtube_options(post))
        when 'tiktok'
          options.merge!(prepare_tiktok_options(post))
        when 'whatsapp'
          options.merge!(prepare_whatsapp_options(post))
        end

        options.merge!(post.post_options || {})
      end

      def prepare_facebook_options(post)
        {
          link: post.product&.url,
          published: true
        }
      end

      def prepare_instagram_options(post)
        {
          caption: post.content,
          media_type: post.media_urls&.any? ? 'IMAGE' : 'TEXT'
        }
      end

      def prepare_youtube_options(post)
        {
          title: post.product&.name || 'Product Showcase',
          description: post.content,
          privacy_status: 'public'
        }
      end

      def prepare_tiktok_options(post)
        {
          privacy_level: 'PUBLIC_TO_EVERYONE',
          disable_duet: false,
          disable_comment: false,
          disable_stitch: false
        }
      end

      def prepare_whatsapp_options(post)
        {
          message_type: 'text',
          recipient_type: 'catalog'
        }
      end
    end
  end
end