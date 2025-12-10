module Spree
  module SocialMedia
    class SendNotificationJob < ApplicationJob
      queue_as :social_media

      def perform(vendor_id, notification_type, notification_data)
        vendor = Spree::Vendor.find(vendor_id)
        Rails.logger.info "Sending #{notification_type} notification for vendor #{vendor.name}"

        begin
          case notification_type
          when 'social_media_comment'
            send_comment_notification(vendor, notification_data)
          when 'social_media_mention'
            send_mention_notification(vendor, notification_data)
          when 'social_media_message'
            send_message_notification(vendor, notification_data)
          when 'engagement_milestone'
            send_milestone_notification(vendor, notification_data)
          when 'compliance_alert'
            send_compliance_notification(vendor, notification_data)
          when 'analytics_report'
            send_analytics_notification(vendor, notification_data)
          when 'post_performance'
            send_performance_notification(vendor, notification_data)
          else
            Rails.logger.warn "Unknown notification type: #{notification_type}"
          end

        rescue => e
          Rails.error.report e
          Rails.logger.error "Failed to send #{notification_type} notification for vendor #{vendor_id}: #{e.message}"
        end
      end

      private

      def send_comment_notification(vendor, data)
        # Send email notification for new comments
        if should_send_email_notification?(vendor, 'comments')
          Spree::SocialMedia::CommentNotificationMailer.new_comment(
            vendor,
            data[:comment_id],
            data[:account_username],
            data[:comment_text],
            data[:from_username]
          ).deliver_now
        end

        # Send in-app notification
        create_in_app_notification(vendor, {
          type: 'comment',
          title: data[:title] || 'New Comment',
          message: data[:message],
          action_url: admin_comment_url(data[:comment_id]),
          priority: determine_notification_priority(data),
          metadata: {
            comment_id: data[:comment_id],
            account_username: data[:account_username],
            sentiment: data[:sentiment]
          }
        })

        # Send push notification if enabled
        if should_send_push_notification?(vendor, 'comments')
          send_push_notification(vendor, data[:title], data[:message])
        end

        # Send Slack/Discord webhook if configured
        send_webhook_notification(vendor, 'comment', data) if webhook_configured?(vendor)
      end

      def send_mention_notification(vendor, data)
        priority = data[:urgency] == 'high' ? 'urgent' : 'normal'

        # Send email for urgent mentions or influencer mentions
        if should_send_email_notification?(vendor, 'mentions') &&
           (data[:urgency] == 'high' || data[:is_influencer])
          Spree::SocialMedia::MentionNotificationMailer.new_mention(
            vendor,
            data[:mention_id],
            data[:account_username],
            data[:message],
            data[:urgency]
          ).deliver_now
        end

        # Send in-app notification
        create_in_app_notification(vendor, {
          type: 'mention',
          title: data[:title] || 'Brand Mention',
          message: data[:message],
          action_url: admin_mention_url(data[:mention_id]),
          priority: priority,
          metadata: {
            mention_id: data[:mention_id],
            account_username: data[:account_username],
            urgency: data[:urgency],
            is_influencer: data[:is_influencer]
          }
        })

        # Send immediate notifications for high-priority mentions
        if data[:urgency] == 'high' && should_send_push_notification?(vendor, 'urgent_mentions')
          send_push_notification(vendor, data[:title], data[:message], urgent: true)
        end

        # Send webhook notification
        send_webhook_notification(vendor, 'mention', data) if webhook_configured?(vendor)
      end

      def send_message_notification(vendor, data)
        # Send email notification for unread messages
        if should_send_email_notification?(vendor, 'messages')
          Spree::SocialMedia::MessageNotificationMailer.new_message(
            vendor,
            data[:message_id],
            data[:account_username],
            data[:message_text],
            data[:from_username]
          ).deliver_now
        end

        # Send in-app notification
        create_in_app_notification(vendor, {
          type: 'message',
          title: data[:title] || 'New Direct Message',
          message: data[:message],
          action_url: admin_message_url(data[:message_id]),
          priority: data[:requires_urgent_attention] ? 'urgent' : 'normal',
          metadata: {
            message_id: data[:message_id],
            account_username: data[:account_username],
            message_type: data[:message_type],
            customer_intent: data[:customer_intent]
          }
        })

        # Send push notification for urgent messages
        if data[:requires_urgent_attention] && should_send_push_notification?(vendor, 'urgent_messages')
          send_push_notification(vendor, data[:title], data[:message], urgent: true)
        end

        # Send webhook notification
        send_webhook_notification(vendor, 'message', data) if webhook_configured?(vendor)
      end

      def send_milestone_notification(vendor, data)
        milestone_type = data[:milestone_type]

        # Send congratulatory email
        if should_send_email_notification?(vendor, 'milestones')
          Spree::SocialMedia::MilestoneNotificationMailer.milestone_achieved(
            vendor,
            data[:milestone_name],
            data[:achievement_value],
            data[:account_username]
          ).deliver_now
        end

        # Send in-app notification
        create_in_app_notification(vendor, {
          type: 'milestone',
          title: data[:title] || 'Milestone Achieved! 🎉',
          message: data[:message],
          action_url: admin_analytics_url,
          priority: 'celebration',
          metadata: {
            milestone_type: milestone_type,
            achievement_value: data[:achievement_value],
            account_username: data[:account_username]
          }
        })

        # Send push notification for major milestones
        if major_milestone?(milestone_type) && should_send_push_notification?(vendor, 'milestones')
          send_push_notification(vendor, data[:title], data[:message], celebration: true)
        end

        # Send webhook notification
        send_webhook_notification(vendor, 'milestone', data) if webhook_configured?(vendor)
      end

      def send_compliance_notification(vendor, data)
        severity = data[:severity] || 'medium'

        # Send immediate email for high-severity compliance issues
        if severity.in?(['high', 'critical']) && should_send_email_notification?(vendor, 'compliance')
          Spree::SocialMedia::ComplianceNotificationMailer.compliance_alert(
            vendor,
            data[:violation_type],
            data[:description],
            data[:recommended_actions],
            severity
          ).deliver_now
        end

        # Send in-app notification
        create_in_app_notification(vendor, {
          type: 'compliance',
          title: data[:title] || 'Compliance Alert',
          message: data[:message],
          action_url: admin_compliance_url,
          priority: severity == 'critical' ? 'urgent' : 'high',
          metadata: {
            violation_type: data[:violation_type],
            severity: severity,
            account_username: data[:account_username]
          }
        })

        # Send immediate push notification for critical issues
        if severity == 'critical' && should_send_push_notification?(vendor, 'critical_alerts')
          send_push_notification(vendor, data[:title], data[:message], urgent: true)
        end

        # Send webhook notification
        send_webhook_notification(vendor, 'compliance', data) if webhook_configured?(vendor)
      end

      def send_analytics_notification(vendor, data)
        report_type = data[:report_type] || 'daily'

        # Send email with analytics summary
        if should_send_email_notification?(vendor, 'analytics_reports')
          Spree::SocialMedia::AnalyticsNotificationMailer.analytics_report(
            vendor,
            data[:report_data],
            data[:period],
            report_type
          ).deliver_now
        end

        # Send in-app notification
        create_in_app_notification(vendor, {
          type: 'analytics',
          title: data[:title] || 'Analytics Report Ready',
          message: data[:message],
          action_url: admin_analytics_url,
          priority: 'low',
          metadata: {
            report_type: report_type,
            period: data[:period]
          }
        })

        # Don't send push notifications for regular analytics reports
        # Only send webhook if specifically configured for analytics
        send_webhook_notification(vendor, 'analytics', data) if webhook_configured?(vendor, 'analytics')
      end

      def send_performance_notification(vendor, data)
        performance_type = data[:performance_type] # 'viral', 'trending', 'low_performance'

        # Send email for exceptional performance (viral posts)
        if performance_type == 'viral' && should_send_email_notification?(vendor, 'performance_alerts')
          Spree::SocialMedia::PerformanceNotificationMailer.viral_post(
            vendor,
            data[:post_id],
            data[:metrics],
            data[:account_username]
          ).deliver_now
        end

        # Send in-app notification
        priority = case performance_type
                   when 'viral', 'trending'
                     'celebration'
                   when 'low_performance'
                     'normal'
                   else
                     'low'
                   end

        create_in_app_notification(vendor, {
          type: 'performance',
          title: data[:title] || 'Post Performance Update',
          message: data[:message],
          action_url: admin_post_url(data[:post_id]),
          priority: priority,
          metadata: {
            post_id: data[:post_id],
            performance_type: performance_type,
            metrics: data[:metrics]
          }
        })

        # Send push notification for viral posts
        if performance_type == 'viral' && should_send_push_notification?(vendor, 'performance_alerts')
          send_push_notification(vendor, data[:title], data[:message], celebration: true)
        end

        # Send webhook notification
        send_webhook_notification(vendor, 'performance', data) if webhook_configured?(vendor)
      end

      def should_send_email_notification?(vendor, category)
        # Check vendor's notification preferences
        preferences = vendor.notification_preferences || {}
        email_preferences = preferences['email'] || {}

        # Default to true if no preference set
        email_preferences.fetch(category, true)
      end

      def should_send_push_notification?(vendor, category)
        preferences = vendor.notification_preferences || {}
        push_preferences = preferences['push'] || {}

        # Default to false for push notifications
        push_preferences.fetch(category, false)
      end

      def webhook_configured?(vendor, specific_category = nil)
        webhook_settings = vendor.webhook_settings || {}
        return false unless webhook_settings['enabled']

        if specific_category
          categories = webhook_settings['categories'] || []
          categories.include?(specific_category)
        else
          webhook_settings['url'].present?
        end
      end

      def create_in_app_notification(vendor, notification_data)
        # This would create a record in an in-app notifications table
        Rails.logger.info "Creating in-app notification for #{vendor.name}: #{notification_data[:title]}"

        # Example of what this might look like:
        # vendor.notifications.create!(
        #   type: notification_data[:type],
        #   title: notification_data[:title],
        #   message: notification_data[:message],
        #   action_url: notification_data[:action_url],
        #   priority: notification_data[:priority],
        #   metadata: notification_data[:metadata],
        #   read_at: nil
        # )
      end

      def send_push_notification(vendor, title, message, options = {})
        # This would send push notifications to mobile apps or browser notifications
        Rails.logger.info "Sending push notification to #{vendor.name}: #{title}"

        # Example implementation would use services like:
        # - Firebase Cloud Messaging for mobile apps
        # - Web Push API for browser notifications
        # - Apple Push Notification service for iOS

        priority = options[:urgent] ? 'high' : 'normal'
        category = if options[:celebration]
                     'milestone'
                   elsif options[:urgent]
                     'urgent'
                   else
                     'normal'
                   end

        Rails.logger.info "Push notification - Priority: #{priority}, Category: #{category}"
      end

      def send_webhook_notification(vendor, event_type, data)
        webhook_settings = vendor.webhook_settings || {}
        webhook_url = webhook_settings['url']

        return unless webhook_url.present?

        payload = {
          vendor_id: vendor.id,
          vendor_name: vendor.name,
          event_type: event_type,
          timestamp: Time.current.iso8601,
          data: data
        }

        # Add webhook signature for security
        signature = generate_webhook_signature(payload, webhook_settings['secret'])

        begin
          HTTParty.post(webhook_url, {
            body: payload.to_json,
            headers: {
              'Content-Type' => 'application/json',
              'X-Webhook-Signature' => signature,
              'User-Agent' => 'Spree-SocialMedia-Webhook/1.0'
            },
            timeout: 5
          })

          Rails.logger.info "Webhook sent successfully to #{webhook_url}"

        rescue => e
          Rails.logger.error "Failed to send webhook to #{webhook_url}: #{e.message}"
        end
      end

      def determine_notification_priority(data)
        return 'urgent' if data[:sentiment] == 'negative'
        return 'high' if data[:requires_response]
        'normal'
      end

      def major_milestone?(milestone_type)
        major_milestones = [
          'followers_10k',
          'followers_100k',
          'followers_1m',
          'viral_post',
          'monthly_reach_1m'
        ]

        major_milestones.include?(milestone_type)
      end

      def generate_webhook_signature(payload, secret)
        return '' unless secret.present?

        "sha256=#{OpenSSL::HMAC.hexdigest('sha256', secret, payload.to_json)}"
      end

      # Helper methods for generating admin URLs
      def admin_comment_url(comment_id)
        "/admin/social_media/comments/#{comment_id}"
      end

      def admin_mention_url(mention_id)
        "/admin/social_media/mentions/#{mention_id}"
      end

      def admin_message_url(message_id)
        "/admin/social_media/messages/#{message_id}"
      end

      def admin_analytics_url
        "/admin/social_media/analytics/dashboard"
      end

      def admin_compliance_url
        "/admin/social_media/compliance"
      end

      def admin_post_url(post_id)
        "/admin/social_media/posts/#{post_id}"
      end
    end
  end
end