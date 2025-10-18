require 'webpush'

module Spree
  class PushNotificationService
    def self.send_to_user(user, title, body, options = {})
      return { success: 0, failure: 0 } if user.nil?

      subscriptions = Spree::PushSubscription.where(user_id: user.id)
      send_to_subscriptions(subscriptions, title, body, options)
    end

    def self.send_to_subscription(subscription, title, body, options = {})
      return { success: 0, failure: 0 } if subscription.nil?

      send_to_subscriptions([subscription], title, body, options)
    end

    def self.broadcast(title, body, options = {})
      subscriptions = Spree::PushSubscription.all
      send_to_subscriptions(subscriptions, title, body, options)
    end

    private

    def self.send_to_subscriptions(subscriptions, title, body, options = {})
      return { success: 0, failure: 0 } if subscriptions.empty?

      payload = {
        title: title,
        body: body,
        icon: options[:icon] || '/icon.png',
        badge: options[:badge] || '/badge.png',
        url: options[:url] || '/'
      }.to_json

      message_options = {
        vapid: {
          subject: "mailto:#{ENV['VAPID_SUBJECT'] || 'webmaster@example.com'}",
          public_key: ENV['VAPID_PUBLIC_KEY'],
          private_key: ENV['VAPID_PRIVATE_KEY'],
          expiration: 12 * 60 * 60 # 12 hours
        }
      }

      results = { success: 0, failure: 0, errors: [] }

      subscriptions.each do |subscription|
        begin
          Webpush.payload_send(
            message: payload,
            endpoint: subscription.endpoint,
            p256dh: subscription.p256dh,
            auth: subscription.auth,
            **message_options
          )

          subscription.update(last_used_at: Time.current)
          results[:success] += 1
        rescue => e
          results[:failure] += 1
          results[:errors] << { subscription_id: subscription.id, error: e.message }

          # Remove subscriptions that are expired or invalid
          if e.message.include?('expired') || e.message.include?('invalid')
            subscription.destroy
          end
        end
      end

      results
    end
  end
end