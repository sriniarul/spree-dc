module Spree
  module SocialMedia
    class ProcessMentionJob < ApplicationJob
      queue_as :social_media

      def perform(mention_id)
        mention = Spree::SocialMediaMention.find(mention_id)
        Rails.logger.info "Processing mention #{mention_id} for account #{mention.social_media_account.username}"

        begin
          # Update mention status
          mention.update!(processed_at: Time.current, status: 'processing')

          # Extract mentioned products if any
          extract_mentioned_products(mention)

          # Analyze mention sentiment and context
          analyze_mention_context(mention)

          # Check if this is an influencer mention
          check_influencer_status(mention)

          # Generate response suggestions if appropriate
          generate_response_suggestions(mention) if mention.requires_response?

          # Create engagement event record
          create_engagement_event(mention)

          # Send notifications if needed
          send_notifications(mention) if mention.notification_worthy?

          # Update mention status to processed
          mention.update!(status: 'processed', processed_at: Time.current)

          Rails.logger.info "Successfully processed mention #{mention_id}"

        rescue => e
          Rails.error.report e
          Rails.logger.error "Failed to process mention #{mention_id}: #{e.message}"
          mention.update!(status: 'error', error_message: e.message)
        end
      end

      private

      def extract_mentioned_products(mention)
        return unless mention.caption.present?

        # Look for product names or SKUs in the mention
        vendor = mention.social_media_account.vendor
        products = vendor.products.published

        mentioned_products = []

        products.each do |product|
          # Check if product name is mentioned (case insensitive)
          if mention.caption.downcase.include?(product.name.downcase)
            mentioned_products << product
          end

          # Check if product SKU is mentioned
          product.variants.each do |variant|
            if variant.sku.present? && mention.caption.include?(variant.sku)
              mentioned_products << product
            end
          end
        end

        if mentioned_products.any?
          mention.update!(
            mentioned_products: mentioned_products.uniq.pluck(:id),
            contains_product_mention: true
          )

          Rails.logger.info "Found #{mentioned_products.count} mentioned products in mention #{mention.id}"
        end
      end

      def analyze_mention_context(mention)
        context_data = {
          intent: extract_mention_intent(mention),
          urgency: assess_mention_urgency(mention),
          opportunity_type: identify_opportunity_type(mention)
        }

        mention.update!(context_data: context_data)
      end

      def extract_mention_intent(mention)
        caption_lower = mention.caption.downcase

        # Complaint or issue
        if caption_lower.match?(/problem|issue|broken|defective|disappointed|angry|terrible|awful|bad/)
          return 'complaint'
        end

        # Compliment or positive feedback
        if caption_lower.match?(/love|amazing|great|awesome|beautiful|fantastic|perfect|excellent/)
          return 'compliment'
        end

        # Purchase inquiry
        if caption_lower.match?(/buy|purchase|price|cost|where.*get|how.*order/)
          return 'purchase_inquiry'
        end

        # Support request
        if caption_lower.match?(/help|support|question|how.*use|tutorial/)
          return 'support_request'
        end

        # Collaboration request
        if caption_lower.match?(/collab|collaboration|partnership|sponsor|ambassador|pr/)
          return 'collaboration'
        end

        # General mention
        'general_mention'
      end

      def assess_mention_urgency(mention)
        urgent_indicators = ['angry', 'terrible', 'awful', 'disappointed', 'problem', 'issue', 'broken', 'defective']
        urgent_count = urgent_indicators.count { |indicator| mention.caption.downcase.include?(indicator) }

        case urgent_count
        when 0
          'low'
        when 1..2
          'medium'
        else
          'high'
        end
      end

      def identify_opportunity_type(mention)
        opportunities = []

        # User-generated content opportunity
        if mention.media_type.in?(['IMAGE', 'VIDEO', 'CAROUSEL_ALBUM']) &&
           mention.caption.downcase.match?(/love|using|wearing|bought/)
          opportunities << 'user_generated_content'
        end

        # Repost opportunity (positive mentions with good engagement)
        if mention.context_data&.dig('intent') == 'compliment' && mention.likes_count.to_i > 10
          opportunities << 'repost_opportunity'
        end

        # Influencer collaboration opportunity
        if mention.from_user_followers_count.to_i > 10000 &&
           mention.context_data&.dig('intent') == 'collaboration'
          opportunities << 'influencer_collaboration'
        end

        # Customer service opportunity
        if mention.context_data&.dig('intent').in?(['complaint', 'support_request'])
          opportunities << 'customer_service'
        end

        opportunities.empty? ? ['general_engagement'] : opportunities
      end

      def check_influencer_status(mention)
        return unless mention.from_user_followers_count.present?

        follower_count = mention.from_user_followers_count

        influence_level = case follower_count
                         when 0...1000
                           'regular'
                         when 1000...10000
                           'micro_influencer'
                         when 10000...100000
                           'mid_tier_influencer'
                         when 100000...1000000
                           'macro_influencer'
                         else
                           'celebrity'
                         end

        mention.update!(
          influence_level: influence_level,
          is_influencer: influence_level != 'regular'
        )

        if mention.is_influencer? && mention.context_data&.dig('intent') == 'collaboration'
          # Create a collaboration opportunity record
          create_collaboration_opportunity(mention)
        end
      end

      def generate_response_suggestions(mention)
        suggestions = []

        case mention.context_data&.dig('intent')
        when 'complaint'
          suggestions = [
            "We're sorry to hear about your experience! Please send us a DM so we can make this right.",
            "Thank you for bringing this to our attention. We'd love to resolve this for you - please message us directly.",
            "We take all feedback seriously. Please reach out to us directly so we can address your concerns."
          ]

        when 'compliment'
          suggestions = [
            "Thank you so much for the kind words! We're thrilled you're happy with your purchase! ❤️",
            "This made our day! Thank you for being such an amazing customer! 🙌",
            "We're so grateful for customers like you! Thanks for sharing the love! ✨"
          ]

        when 'purchase_inquiry'
          suggestions = [
            "Thanks for your interest! You can find more details on our website or feel free to DM us with any questions!",
            "We'd love to help you find the perfect item! Check out our website or send us a message!",
            "Great question! Please visit our website or DM us for more information and personalized recommendations!"
          ]

        when 'collaboration'
          suggestions = [
            "Thanks for reaching out! Please send us a DM with your collaboration proposal and we'll get back to you!",
            "We love working with creators! Please DM us your media kit and let's discuss opportunities!",
            "Thank you for your interest in collaborating! Please send us a direct message to get started!"
          ]

        else
          suggestions = [
            "Thanks for the mention! We really appreciate your support! 💙",
            "Thank you for thinking of us! We're here if you need anything! 😊",
            "We appreciate you sharing! Thanks for being part of our community! 🙏"
          ]
        end

        mention.update!(response_suggestions: suggestions)
      end

      def create_engagement_event(mention)
        Spree::SocialMediaEngagementEvent.create!(
          social_media_account: mention.social_media_account,
          platform_event_id: mention.platform_mention_id,
          event_type: 'mention',
          event_data: {
            mention_id: mention.id,
            from_user: mention.from_user_data,
            caption: mention.caption.truncate(500),
            media_type: mention.media_type,
            mentions_count: 1,
            influence_level: mention.influence_level
          },
          occurred_at: mention.mentioned_at
        )
      end

      def send_notifications(mention)
        return unless should_send_notification?(mention)

        # Send to vendor admins
        vendor = mention.social_media_account.vendor

        notification_data = {
          type: 'social_media_mention',
          title: generate_notification_title(mention),
          message: generate_notification_message(mention),
          mention_id: mention.id,
          account_username: mention.social_media_account.username,
          urgency: mention.context_data&.dig('urgency') || 'medium'
        }

        Spree::SocialMedia::SendNotificationJob.perform_later(
          vendor.id,
          'social_media_mention',
          notification_data
        )

        mention.update!(notification_sent_at: Time.current)
      end

      def create_collaboration_opportunity(mention)
        opportunity_data = {
          mention_id: mention.id,
          influencer_username: mention.from_user_username,
          follower_count: mention.from_user_followers_count,
          influence_level: mention.influence_level,
          mention_caption: mention.caption,
          opportunity_type: 'collaboration_request',
          status: 'pending_review',
          created_from_mention_at: mention.mentioned_at
        }

        # This would be stored in a collaboration opportunities table
        Rails.logger.info "Collaboration opportunity identified: #{opportunity_data}"
      end

      def should_send_notification?(mention)
        # Send notifications for high-value mentions
        return true if mention.is_influencer?
        return true if mention.context_data&.dig('urgency') == 'high'
        return true if mention.context_data&.dig('intent').in?(['complaint', 'collaboration'])

        false
      end

      def generate_notification_title(mention)
        case mention.context_data&.dig('intent')
        when 'complaint'
          "⚠️ Customer Complaint Mention"
        when 'collaboration'
          "🤝 Collaboration Request"
        when 'compliment'
          "❤️ Positive Brand Mention"
        else
          "📢 Brand Mention"
        end
      end

      def generate_notification_message(mention)
        username = mention.from_user_username
        follower_count = mention.from_user_followers_count&.to_i || 0

        base_message = "@#{username}"
        base_message += " (#{format_follower_count(follower_count)} followers)" if follower_count > 1000
        base_message += " mentioned your brand"

        case mention.context_data&.dig('intent')
        when 'complaint'
          base_message += " with a complaint. Immediate response recommended."
        when 'collaboration'
          base_message += " for a potential collaboration opportunity."
        when 'compliment'
          base_message += " with positive feedback. Great opportunity to engage!"
        else
          base_message += ". Consider responding to build engagement."
        end

        base_message
      end

      def format_follower_count(count)
        if count >= 1_000_000
          "#{(count / 1_000_000.0).round(1)}M"
        elsif count >= 1_000
          "#{(count / 1_000.0).round(1)}K"
        else
          count.to_s
        end
      end
    end
  end
end