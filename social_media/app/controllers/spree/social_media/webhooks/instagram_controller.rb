module Spree
  module SocialMedia
    module Webhooks
      class InstagramController < ApplicationController
        skip_before_action :verify_authenticity_token
        before_action :verify_webhook_signature, only: [:create]
        before_action :log_webhook_request

        # Instagram webhook verification (GET request)
        def verify
          challenge = params['hub.challenge']
          verify_token = params['hub.verify_token']

          if verify_token == webhook_verify_token
            Rails.logger.info "Instagram webhook verified successfully"
            render plain: challenge, status: :ok
          else
            Rails.logger.error "Instagram webhook verification failed - invalid verify token"
            render plain: 'Verification failed', status: :forbidden
          end
        end

        # Instagram webhook events (POST request)
        def create
          begin
            webhook_data = JSON.parse(request.body.read)

            Rails.logger.info "Instagram webhook received: #{webhook_data.inspect}"

            # Process webhook data
            process_webhook_events(webhook_data)

            render json: { status: 'success' }, status: :ok

          rescue JSON::ParserError => e
            Rails.logger.error "Instagram webhook JSON parse error: #{e.message}"
            render json: { error: 'Invalid JSON' }, status: :bad_request
          rescue => e
            Rails.logger.error "Instagram webhook processing error: #{e.message}"
            Rails.logger.error e.backtrace.join("\n")
            render json: { error: 'Processing failed' }, status: :internal_server_error
          end
        end

        private

        def verify_webhook_signature
          signature = request.headers['X-Hub-Signature-256']

          unless signature
            Rails.logger.error "Instagram webhook missing signature"
            render json: { error: 'Missing signature' }, status: :unauthorized
            return false
          end

          # Remove 'sha256=' prefix
          signature = signature.gsub('sha256=', '')

          # Calculate expected signature
          body = request.body.read
          request.body.rewind

          expected_signature = OpenSSL::HMAC.hexdigest(
            OpenSSL::Digest.new('sha256'),
            webhook_app_secret,
            body
          )

          unless Rack::Utils.secure_compare(signature, expected_signature)
            Rails.logger.error "Instagram webhook signature verification failed"
            render json: { error: 'Invalid signature' }, status: :unauthorized
            return false
          end

          true
        end

        def log_webhook_request
          Rails.logger.info "Instagram webhook request: #{request.method} #{request.path}"
          Rails.logger.info "Headers: #{request.headers.select { |k,v| k.start_with?('HTTP_') }.to_h}"
        end

        def process_webhook_events(webhook_data)
          return unless webhook_data['entry']&.any?

          webhook_data['entry'].each do |entry|
            process_entry(entry)
          end
        end

        def process_entry(entry)
          user_id = entry['id']
          time = entry['time']

          Rails.logger.info "Processing Instagram webhook entry for user #{user_id} at #{Time.at(time)}"

          # Find the associated social media account
          account = find_account_by_platform_user_id(user_id)
          unless account
            Rails.logger.warn "No social media account found for Instagram user ID: #{user_id}"
            return
          end

          # Process different types of changes
          entry['changes']&.each do |change|
            process_change(account, change, time)
          end

          # Process messaging events if present
          entry['messaging']&.each do |message|
            process_messaging_event(account, message)
          end

          # Process mentions if present
          entry['mentions']&.each do |mention|
            process_mention_event(account, mention)
          end
        end

        def process_change(account, change, time)
          field = change['field']
          value = change['value']

          Rails.logger.info "Processing Instagram change: #{field} for account #{account.username}"

          case field
          when 'comments'
            process_comment_event(account, value, time)
          when 'likes'
            process_like_event(account, value, time)
          when 'story_insights'
            process_story_insights_event(account, value, time)
          when 'live_comments'
            process_live_comment_event(account, value, time)
          when 'mentions'
            process_mention_change(account, value, time)
          when 'media'
            process_media_event(account, value, time)
          else
            Rails.logger.info "Unknown Instagram webhook field: #{field}"
            log_unknown_event(account, field, value, time)
          end
        end

        def process_comment_event(account, comment_data, time)
          Rails.logger.info "Processing comment event for #{account.username}"

          # Extract comment information
          comment_id = comment_data['id']
          parent_id = comment_data['parent_id'] # For replies
          media_id = comment_data['media']['id'] if comment_data['media']
          text = comment_data['text']
          from_user = comment_data['from']

          # Find the associated post
          post = account.social_media_posts.find_by(platform_post_id: media_id) if media_id

          # Create or update comment record
          comment = create_or_update_comment(account, post, comment_data, time)

          # Queue job to process comment (sentiment analysis, auto-reply, etc.)
          Spree::SocialMedia::ProcessCommentJob.perform_later(comment.id) if comment

          # Trigger notifications if configured
          trigger_comment_notifications(account, comment, post) if comment
        rescue => e
          Rails.logger.error "Error processing comment event: #{e.message}"
        end

        def process_like_event(account, like_data, time)
          Rails.logger.info "Processing like event for #{account.username}"

          media_id = like_data['media_id']
          user_id = like_data['user_id']

          # Find the associated post
          post = account.social_media_posts.find_by(platform_post_id: media_id) if media_id

          if post
            # Update post engagement metrics
            post.increment!(:likes_count) if like_data['verb'] == 'add'
            post.decrement!(:likes_count) if like_data['verb'] == 'remove'

            # Create engagement event record
            create_engagement_event(account, post, 'like', like_data, time)

            # Update analytics if significant milestone
            check_engagement_milestones(post)
          end
        rescue => e
          Rails.logger.error "Error processing like event: #{e.message}"
        end

        def process_story_insights_event(account, insights_data, time)
          Rails.logger.info "Processing story insights event for #{account.username}"

          story_id = insights_data['story_id']
          metrics = insights_data['insights']

          # Find the associated story post
          story = account.social_media_posts.find_by(
            platform_post_id: story_id,
            content_type: 'story'
          )

          if story && metrics
            # Update story analytics
            update_story_analytics(story, metrics, time)

            # Check for story milestones
            check_story_milestones(story, metrics)
          end
        rescue => e
          Rails.logger.error "Error processing story insights: #{e.message}"
        end

        def process_mention_event(account, mention_data)
          Rails.logger.info "Processing mention event for #{account.username}"

          media_id = mention_data['media_id']
          comment_id = mention_data['comment_id']
          from_user = mention_data['from']

          # Create mention record
          mention = create_mention_record(account, mention_data)

          # Queue job to process mention (respond, analyze, etc.)
          Spree::SocialMedia::ProcessMentionJob.perform_later(mention.id) if mention

          # Trigger mention notifications
          trigger_mention_notifications(account, mention) if mention
        rescue => e
          Rails.logger.error "Error processing mention event: #{e.message}"
        end

        def process_media_event(account, media_data, time)
          Rails.logger.info "Processing media event for #{account.username}"

          media_id = media_data['id']
          media_type = media_data['media_type']

          # Find or create post record
          post = account.social_media_posts.find_or_create_by(platform_post_id: media_id) do |p|
            p.content_type = map_media_type_to_content_type(media_type)
            p.status = 'published'
            p.published_at = Time.at(time)
          end

          # Queue job to sync full post data
          Spree::SocialMedia::SyncPostDataJob.perform_later(post.id)
        rescue => e
          Rails.logger.error "Error processing media event: #{e.message}"
        end

        def process_messaging_event(account, message_data)
          Rails.logger.info "Processing messaging event for #{account.username}"

          # This handles direct messages through Instagram messaging
          sender = message_data['sender']
          recipient = message_data['recipient']
          message = message_data['message']

          # Create message record
          create_message_record(account, message_data)

          # Queue job to process message (auto-reply, customer service, etc.)
          Spree::SocialMedia::ProcessMessageJob.perform_later(account.id, message_data)
        rescue => e
          Rails.logger.error "Error processing messaging event: #{e.message}"
        end

        def find_account_by_platform_user_id(user_id)
          Spree::SocialMediaAccount.active
                                   .where(platform: 'instagram')
                                   .where(platform_account_id: user_id)
                                   .first
        end

        def create_or_update_comment(account, post, comment_data, time)
          comment = Spree::SocialMediaComment.find_or_initialize_by(
            social_media_account: account,
            platform_comment_id: comment_data['id']
          )

          comment.assign_attributes(
            social_media_post: post,
            commenter_id: comment_data['from']['id'],
            commenter_username: comment_data['from']['username'],
            text: comment_data['text'],
            parent_comment_id: comment_data['parent_id'],
            commented_at: Time.at(time),
            metadata: comment_data.to_json
          )

          comment.save!
          comment
        rescue => e
          Rails.logger.error "Error creating comment record: #{e.message}"
          nil
        end

        def create_engagement_event(account, post, event_type, event_data, time)
          Spree::SocialMediaEngagementEvent.create!(
            social_media_account: account,
            social_media_post: post,
            event_type: event_type,
            user_id: event_data['user_id'],
            event_data: event_data.to_json,
            occurred_at: Time.at(time)
          )
        rescue => e
          Rails.logger.error "Error creating engagement event: #{e.message}"
        end

        def create_mention_record(account, mention_data)
          Spree::SocialMediaMention.create!(
            social_media_account: account,
            platform_mention_id: mention_data['id'],
            media_id: mention_data['media_id'],
            comment_id: mention_data['comment_id'],
            from_user_id: mention_data['from']['id'],
            from_username: mention_data['from']['username'],
            mention_type: determine_mention_type(mention_data),
            metadata: mention_data.to_json,
            occurred_at: Time.current
          )
        rescue => e
          Rails.logger.error "Error creating mention record: #{e.message}"
          nil
        end

        def create_message_record(account, message_data)
          Spree::SocialMediaMessage.create!(
            social_media_account: account,
            platform_message_id: message_data['mid'],
            sender_id: message_data['sender']['id'],
            recipient_id: message_data['recipient']['id'],
            message_text: message_data['message']['text'],
            message_type: 'direct_message',
            metadata: message_data.to_json,
            received_at: Time.current
          )
        rescue => e
          Rails.logger.error "Error creating message record: #{e.message}"
          nil
        end

        def update_story_analytics(story, metrics, time)
          analytics = story.social_media_analytics.find_or_create_by(
            date: Time.at(time).to_date
          )

          analytics.update!(
            story_impressions: metrics['impressions'],
            story_reach: metrics['reach'],
            story_replies: metrics['replies'],
            story_exits: metrics['exits'],
            story_taps_forward: metrics['taps_forward'],
            story_taps_back: metrics['taps_back'],
            raw_data: metrics.to_json,
            synced_at: Time.current
          )
        end

        def check_engagement_milestones(post)
          return unless post.likes_count && post.likes_count > 0

          # Check for like milestones
          milestone_thresholds = [100, 500, 1000, 5000, 10000]

          milestone_thresholds.each do |threshold|
            if post.likes_count >= threshold
              # Check if milestone already exists
              existing_milestone = Spree::SocialMediaMilestone.find_by(
                social_media_post: post,
                milestone_type: "likes_#{threshold}"
              )

              unless existing_milestone
                Spree::SocialMediaMilestone.create!(
                  social_media_account: post.social_media_account,
                  social_media_post: post,
                  milestone_type: "likes_#{threshold}",
                  message: "Post reached #{threshold} likes!",
                  achieved_at: Time.current,
                  metrics_data: {
                    likes_count: post.likes_count,
                    comments_count: post.comments_count,
                    shares_count: post.shares_count
                  }.to_json
                )

                # Trigger milestone notifications
                trigger_milestone_notifications(post, "likes_#{threshold}")
              end
            end
          end
        end

        def check_story_milestones(story, metrics)
          reach = metrics['reach'].to_i

          if reach >= 1000 && reach < 1100 # Recently crossed 1k
            create_story_milestone(story, 'story_reach_1k', 'Story reached 1,000+ people!', metrics)
          elsif reach >= 10000 && reach < 10100 # Recently crossed 10k
            create_story_milestone(story, 'story_reach_10k', 'Story reached 10,000+ people!', metrics)
          end
        end

        def create_story_milestone(story, milestone_type, message, metrics)
          existing = Spree::SocialMediaMilestone.find_by(
            social_media_post: story,
            milestone_type: milestone_type
          )

          return if existing

          Spree::SocialMediaMilestone.create!(
            social_media_account: story.social_media_account,
            social_media_post: story,
            milestone_type: milestone_type,
            message: message,
            achieved_at: Time.current,
            metrics_data: metrics.to_json
          )
        end

        def map_media_type_to_content_type(media_type)
          case media_type
          when 'VIDEO'
            'reel'
          when 'CAROUSEL_ALBUM'
            'carousel'
          when 'IMAGE'
            'post'
          else
            'post'
          end
        end

        def determine_mention_type(mention_data)
          if mention_data['media_id']
            'post_mention'
          elsif mention_data['comment_id']
            'comment_mention'
          else
            'story_mention'
          end
        end

        def trigger_comment_notifications(account, comment, post)
          return unless account.vendor.notification_preferences&.dig('new_comment')

          # Queue notification job
          Spree::SocialMedia::SendNotificationJob.perform_later(
            account.vendor.id,
            'new_comment',
            {
              comment_id: comment.id,
              post_id: post&.id,
              commenter: comment.commenter_username,
              text: comment.text.truncate(100)
            }
          )
        end

        def trigger_mention_notifications(account, mention)
          return unless account.vendor.notification_preferences&.dig('new_mention')

          # Queue notification job
          Spree::SocialMedia::SendNotificationJob.perform_later(
            account.vendor.id,
            'new_mention',
            {
              mention_id: mention.id,
              from_user: mention.from_username,
              mention_type: mention.mention_type
            }
          )
        end

        def trigger_milestone_notifications(post, milestone_type)
          account = post.social_media_account
          return unless account.vendor.notification_preferences&.dig('milestone_achieved')

          # Queue notification job
          Spree::SocialMedia::SendNotificationJob.perform_later(
            account.vendor.id,
            'milestone_achieved',
            {
              post_id: post.id,
              milestone_type: milestone_type,
              post_caption: post.caption&.truncate(100)
            }
          )
        end

        def log_unknown_event(account, field, value, time)
          Rails.logger.info "Unknown Instagram webhook event logged for #{account.username}"

          # Store unknown events for analysis
          Spree::SocialMediaWebhookEvent.create!(
            social_media_account: account,
            event_type: 'unknown',
            field_name: field,
            event_data: value.to_json,
            occurred_at: Time.at(time),
            processed: false
          )
        end

        def webhook_verify_token
          Rails.application.credentials.dig(:facebook, :webhook_verify_token) ||
            ENV['FACEBOOK_WEBHOOK_VERIFY_TOKEN'] ||
            'default_verify_token_change_in_production'
        end

        def webhook_app_secret
          Rails.application.credentials.dig(:facebook, :app_secret) ||
            ENV['FACEBOOK_APP_SECRET'] ||
            raise('Instagram webhook app secret not configured')
        end
      end
    end
  end
end