module Spree
  module SocialMedia
    class ProcessCommentJob < ApplicationJob
      queue_as :social_media

      retry_on StandardError, wait: :exponentially_longer, attempts: 3

      def perform(comment_id)
        @comment = Spree::SocialMediaComment.find(comment_id)
        @account = @comment.social_media_account
        @vendor = @account.vendor

        Rails.logger.info "Processing comment #{comment_id} for account #{@account.username}"

        begin
          # Perform comprehensive comment analysis and processing
          analyze_comment_sentiment
          detect_spam_or_inappropriate_content
          extract_actionable_insights
          generate_auto_reply_if_configured
          update_engagement_metrics
          trigger_notifications_if_needed
          check_for_customer_service_escalation

          # Mark comment as processed
          @comment.mark_as_processed!

          Rails.logger.info "Successfully processed comment #{comment_id}"

        rescue => e
          Rails.logger.error "Failed to process comment #{comment_id}: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          raise
        end
      end

      private

      def analyze_comment_sentiment
        return if @comment.text.blank?

        # Enhanced sentiment analysis
        sentiment_result = perform_advanced_sentiment_analysis(@comment.text)

        @comment.update!(
          sentiment_score: sentiment_result[:score],
          confidence_level: sentiment_result[:confidence],
          detected_emotions: sentiment_result[:emotions].to_json
        )

        Rails.logger.info "Sentiment analysis complete: #{sentiment_result[:score]} (#{@comment.sentiment_label})"
      end

      def detect_spam_or_inappropriate_content
        spam_indicators = []
        inappropriate_flags = []

        # Check for spam patterns
        spam_indicators << 'excessive_emojis' if excessive_emojis?
        spam_indicators << 'repeated_characters' if repeated_characters?
        spam_indicators << 'promotional_links' if contains_promotional_links?
        spam_indicators << 'bot_behavior' if bot_like_behavior?

        # Check for inappropriate content
        inappropriate_flags << 'profanity' if contains_profanity?
        inappropriate_flags << 'harassment' if contains_harassment?
        inappropriate_flags << 'threats' if contains_threats?

        if spam_indicators.any? || inappropriate_flags.any?
          @comment.update!(
            flagged_as_spam: spam_indicators.any?,
            flagged_as_inappropriate: inappropriate_flags.any?,
            moderation_flags: (spam_indicators + inappropriate_flags).to_json,
            requires_moderation: true
          )

          # Create moderation task
          create_moderation_task(spam_indicators + inappropriate_flags)
        end
      end

      def extract_actionable_insights
        insights = []

        # Extract customer feedback themes
        if customer_feedback?
          insights << extract_feedback_themes
        end

        # Identify product mentions
        if product_mentions?
          insights << extract_product_mentions
        end

        # Detect customer service opportunities
        if customer_service_opportunity?
          insights << 'customer_service_opportunity'
        end

        # Identify influencer engagement
        if potential_influencer?
          insights << 'influencer_engagement'
        end

        @comment.update!(
          actionable_insights: insights.flatten.compact.to_json
        ) if insights.any?
      end

      def generate_auto_reply_if_configured
        return unless @vendor.auto_reply_enabled?
        return if @comment.reply? # Don't auto-reply to replies

        auto_reply_config = @vendor.auto_reply_settings || {}

        should_reply = case @comment.sentiment_label
                      when 'positive'
                        auto_reply_config['reply_to_positive']
                      when 'negative'
                        auto_reply_config['reply_to_negative']
                      when 'neutral'
                        auto_reply_config['reply_to_neutral']
                      else
                        false
                      end

        return unless should_reply

        # Generate contextual auto-reply
        reply_text = generate_contextual_reply

        if reply_text
          # Queue job to post the reply
          Spree::SocialMedia::PostCommentReplyJob.perform_later(
            @comment.id,
            reply_text
          )

          Rails.logger.info "Queued auto-reply for comment #{@comment.id}"
        end
      end

      def update_engagement_metrics
        return unless @comment.social_media_post

        post = @comment.social_media_post

        # Update post comment count
        post.increment!(:comments_count)

        # Update post engagement metrics
        post.touch(:last_engagement_at)

        # Create engagement event
        Spree::SocialMediaEngagementEvent.create!(
          social_media_account: @account,
          social_media_post: post,
          event_type: 'comment',
          user_id: @comment.commenter_id,
          event_data: {
            comment_id: @comment.id,
            commenter_username: @comment.commenter_username,
            sentiment: @comment.sentiment_label
          }.to_json,
          occurred_at: @comment.commented_at
        )

        # Check for engagement milestones
        check_comment_milestones(post)
      end

      def trigger_notifications_if_needed
        notification_settings = @vendor.notification_preferences || {}

        # New comment notification
        if notification_settings['new_comment']
          send_new_comment_notification
        end

        # Negative comment notification
        if notification_settings['negative_comment'] && @comment.sentiment_label == 'negative'
          send_negative_comment_notification
        end

        # High-priority comment notification
        if notification_settings['priority_comment'] && @comment.requires_attention?
          send_priority_comment_notification
        end

        # Mention notification (if comment contains brand mention)
        if notification_settings['brand_mention'] && contains_brand_mention?
          send_brand_mention_notification
        end
      end

      def check_for_customer_service_escalation
        escalation_triggers = []

        # Negative sentiment with specific keywords
        if @comment.sentiment_label == 'negative' && contains_service_keywords?
          escalation_triggers << 'negative_service_request'
        end

        # Multiple negative comments from same user
        if repeat_negative_commenter?
          escalation_triggers << 'repeat_negative_commenter'
        end

        # High-influence user complaint
        if high_influence_user? && @comment.sentiment_label == 'negative'
          escalation_triggers << 'influencer_complaint'
        end

        if escalation_triggers.any?
          create_customer_service_ticket(escalation_triggers)
        end
      end

      def perform_advanced_sentiment_analysis(text)
        # This would integrate with advanced NLP services like AWS Comprehend,
        # Google Cloud Natural Language, or Azure Text Analytics

        # For now, implement enhanced local analysis
        emotions = detect_emotions(text)
        confidence = calculate_confidence(text)

        # Simple but improved sentiment scoring
        positive_words = %w[
          love amazing awesome great fantastic wonderful excellent perfect beautiful
          happy good best brilliant outstanding superb marvelous incredible
        ]

        negative_words = %w[
          hate terrible awful bad worst disappointed angry upset problem issue
          horrible disgusting pathetic useless worthless annoying frustrating
        ]

        neutral_words = %w[
          okay fine alright decent average normal standard regular typical
        ]

        words = text.downcase.split(/\W+/)

        positive_count = words.count { |word| positive_words.include?(word) }
        negative_count = words.count { |word| negative_words.include?(word) }
        neutral_count = words.count { |word| neutral_words.include?(word) }

        total_sentiment_words = positive_count + negative_count + neutral_count

        score = if total_sentiment_words > 0
                  (positive_count + (neutral_count * 0.5)) / total_sentiment_words
                else
                  0.5
                end

        {
          score: score,
          confidence: confidence,
          emotions: emotions
        }
      end

      def detect_emotions(text)
        emotions = {}

        # Joy/Happiness indicators
        joy_words = %w[happy joy excited thrilled delighted pleased glad cheerful]
        emotions[:joy] = joy_words.any? { |word| text.downcase.include?(word) }

        # Anger indicators
        anger_words = %w[angry mad furious outraged irritated annoyed frustrated]
        emotions[:anger] = anger_words.any? { |word| text.downcase.include?(word) }

        # Sadness indicators
        sadness_words = %w[sad disappointed upset hurt depressed devastated]
        emotions[:sadness] = sadness_words.any? { |word| text.downcase.include?(word) }

        # Fear/Concern indicators
        fear_words = %w[worried concerned scared afraid nervous anxious]
        emotions[:fear] = fear_words.any? { |word| text.downcase.include?(word) }

        # Surprise indicators
        surprise_words = %w[surprised amazed shocked stunned astonished]
        emotions[:surprise] = surprise_words.any? { |word| text.downcase.include?(word) }

        emotions
      end

      def calculate_confidence(text)
        # Base confidence on text length and sentiment word density
        word_count = text.split(/\W+/).length

        if word_count < 3
          0.3
        elsif word_count < 10
          0.6
        else
          0.8
        end
      end

      def excessive_emojis?
        emoji_count = @comment.text.scan(/[\u{1F600}-\u{1F64F}]|[\u{1F300}-\u{1F5FF}]|[\u{1F680}-\u{1F6FF}]|[\u{1F1E0}-\u{1F1FF}]/).length
        emoji_count > (@comment.text.length * 0.3) # More than 30% emojis
      end

      def repeated_characters?
        @comment.text.match?(/(.)\1{4,}/) # Same character repeated 5+ times
      end

      def contains_promotional_links?
        # Check for common promotional link patterns
        promotional_patterns = [
          /bit\.ly\/\w+/,
          /tinyurl\.com\/\w+/,
          /goo\.gl\/\w+/,
          /www\.\w+\.com/,
          /http[s]?:\/\/\w+/,
          /\b(buy|purchase|discount|deal|offer|sale)\b.*\b(link|url|site|website)\b/i
        ]

        promotional_patterns.any? { |pattern| @comment.text.match?(pattern) }
      end

      def bot_like_behavior?
        # Simple bot detection based on patterns
        bot_patterns = [
          /^(nice|good|great|amazing)\s*(post|pic|photo|content)[\s!]*$/i,
          /^(love|like)\s*(this|it)[\s!]*$/i,
          /^follow\s+me[\s!]*$/i
        ]

        bot_patterns.any? { |pattern| @comment.text.strip.match?(pattern) }
      end

      def contains_profanity?
        # This would integrate with a profanity detection service
        # For now, basic word list check
        profanity_words = %w[spam fake scam stupid idiot] # Simplified list

        words = @comment.text.downcase.split(/\W+/)
        profanity_words.any? { |profane_word| words.include?(profane_word) }
      end

      def contains_harassment?
        harassment_indicators = [
          /you\s+(are|suck|stupid)/i,
          /shut\s+up/i,
          /go\s+away/i,
          /nobody\s+cares/i
        ]

        harassment_indicators.any? { |pattern| @comment.text.match?(pattern) }
      end

      def contains_threats?
        threat_patterns = [
          /i('ll|\s+will)\s+report/i,
          /you('ll|\s+will)\s+regret/i,
          /watch\s+out/i,
          /i\s+know\s+where/i
        ]

        threat_patterns.any? { |pattern| @comment.text.match?(pattern) }
      end

      def customer_feedback?
        feedback_keywords = %w[
          feedback suggestion improve better quality service experience
          recommend recommendation issue problem complaint
        ]

        feedback_keywords.any? { |keyword| @comment.text.downcase.include?(keyword) }
      end

      def product_mentions?
        # Check if comment mentions specific products
        @comment.text.match?(/\b(product|item|quality|price|shipping|delivery)\b/i)
      end

      def customer_service_opportunity?
        service_keywords = %w[
          help support assistance question problem issue refund return
          exchange complaint concern contact
        ]

        service_keywords.any? { |keyword| @comment.text.downcase.include?(keyword) }
      end

      def potential_influencer?
        # This would check the commenter's follower count and engagement metrics
        # For now, simple username pattern check
        username = @comment.commenter_username.to_s

        # Check for verified account indicators or high follower count patterns
        username.match?(/^[a-z0-9_]{3,}$/) && !username.match?(/\d{4,}/) # Not auto-generated looking
      end

      def extract_feedback_themes
        themes = []
        text = @comment.text.downcase

        themes << 'product_quality' if text.match?(/\b(quality|material|build|construction)\b/)
        themes << 'customer_service' if text.match?(/\b(service|support|staff|help)\b/)
        themes << 'shipping_delivery' if text.match?(/\b(shipping|delivery|arrived|package)\b/)
        themes << 'pricing' if text.match?(/\b(price|cost|expensive|cheap|value)\b/)
        themes << 'website_experience' if text.match?(/\b(website|site|online|order)\b/)

        themes
      end

      def extract_product_mentions
        # This would analyze the comment for specific product names or SKUs
        # For now, return generic product mention flag
        ['product_mention']
      end

      def generate_contextual_reply
        suggestions = @comment.generate_auto_reply_suggestions

        # Select most appropriate reply based on context
        case @comment.sentiment_label
        when 'positive'
          suggestions.select { |s| s.include?('Thank') || s.include?('appreciate') }.first
        when 'negative'
          suggestions.select { |s| s.include?('sorry') || s.include?('apologize') }.first
        else
          suggestions.first
        end
      end

      def check_comment_milestones(post)
        comments_count = post.comments_count

        milestone_thresholds = [10, 25, 50, 100, 500, 1000]

        milestone_thresholds.each do |threshold|
          if comments_count == threshold
            Spree::SocialMediaMilestone.create!(
              social_media_account: @account,
              social_media_post: post,
              milestone_type: "comments_#{threshold}",
              message: "Post reached #{threshold} comments!",
              achieved_at: Time.current,
              metrics_data: {
                comments_count: comments_count,
                likes_count: post.likes_count,
                engagement_rate: post.engagement_rate
              }.to_json
            )
          end
        end
      end

      def contains_service_keywords?
        service_keywords = %w[help support problem issue refund return complaint]
        service_keywords.any? { |keyword| @comment.text.downcase.include?(keyword) }
      end

      def repeat_negative_commenter?
        recent_comments = Spree::SocialMediaComment
                           .where(social_media_account: @account)
                           .where(commenter_id: @comment.commenter_id)
                           .where('commented_at > ?', 30.days.ago)
                           .where('sentiment_score < ?', 0.4)

        recent_comments.count >= 3
      end

      def high_influence_user?
        # This would check against a database of known influencers
        # For now, simple heuristics
        username = @comment.commenter_username.to_s

        # Check for blue checkmark pattern or known influencer indicators
        username.length < 15 && !username.match?(/\d{3,}/)
      end

      def contains_brand_mention?
        brand_names = [@vendor.name, @vendor.display_name].compact.map(&:downcase)
        brand_names.any? { |name| @comment.text.downcase.include?(name) }
      end

      def create_moderation_task(flags)
        Rails.logger.info "Creating moderation task for comment #{@comment.id} with flags: #{flags.join(', ')}"

        # This would create a task for human moderators
        # For now, just log the requirement
      end

      def create_customer_service_ticket(triggers)
        Rails.logger.info "Creating customer service ticket for comment #{@comment.id} with triggers: #{triggers.join(', ')}"

        # This would integrate with customer service systems
        # For now, just log the requirement
      end

      def send_new_comment_notification
        Rails.logger.info "Sending new comment notification for comment #{@comment.id}"
        # Implementation for sending notification
      end

      def send_negative_comment_notification
        Rails.logger.info "Sending negative comment notification for comment #{@comment.id}"
        # Implementation for sending notification
      end

      def send_priority_comment_notification
        Rails.logger.info "Sending priority comment notification for comment #{@comment.id}"
        # Implementation for sending notification
      end

      def send_brand_mention_notification
        Rails.logger.info "Sending brand mention notification for comment #{@comment.id}"
        # Implementation for sending notification
      end
    end
  end
end