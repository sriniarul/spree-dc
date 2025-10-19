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

      # Handle OpenSSL 3.0 compatibility by creating VAPID options properly
      vapid_options = build_vapid_options

      results = { success: 0, failure: 0, errors: [] }

      subscriptions.each do |subscription|
        begin
          # Use helper method to handle OpenSSL 3.0 compatibility
          send_notification_with_retry(subscription, payload, vapid_options)

          subscription.update(last_used_at: Time.current)
          results[:success] += 1
        rescue => e
          results[:failure] += 1
          results[:errors] << { subscription_id: subscription.id, error: e.message }

          # Remove subscriptions that are expired or invalid
          if e.message.include?('expired') || e.message.include?('invalid') || e.message.include?('unsubscribed')
            subscription.destroy
          end
        end
      end

      results
    end

    def self.build_vapid_options
      # For OpenSSL 3.0 compatibility, ensure we have proper keys
      public_key = ENV['VAPID_PUBLIC_KEY']
      private_key = ENV['VAPID_PRIVATE_KEY']

      # Generate new keys if missing (for development/testing)
      if public_key.nil? || private_key.nil?
        Rails.logger.warn "VAPID keys not found in environment. Generating temporary keys..."

        # Use a more reliable key generation method for OpenSSL 3.0
        begin
          # Try using Webpush.generate_key first
          vapid_key = Webpush.generate_key
          public_key = vapid_key.public_key
          private_key = vapid_key.private_key
        rescue => e
          Rails.logger.error "Failed to generate keys with Webpush.generate_key: #{e.message}"

          # Fallback: generate keys manually using OpenSSL
          require 'openssl'
          require 'base64'

          # Generate P-256 key pair
          key = OpenSSL::PKey::EC.generate('prime256v1')

          # Extract private key (32 bytes)
          private_key_raw = key.private_key.to_s(2).ljust(32, "\x00")[0, 32]
          private_key = Base64.urlsafe_encode64(private_key_raw).tr('=', '')

          # Extract public key (65 bytes uncompressed)
          public_key_point = key.public_key
          public_key_raw = public_key_point.to_octet_string(:uncompressed)
          public_key = Base64.urlsafe_encode64(public_key_raw).tr('=', '')
        end

        Rails.logger.info "Generated VAPID keys - Public: #{public_key[0..20]}..."
      end

      {
        subject: "mailto:#{ENV['VAPID_SUBJECT'] || 'webmaster@dimecart.com'}",
        public_key: public_key,
        private_key: private_key,
        expiration: 12 * 60 * 60 # 12 hours
      }
    end

    def self.send_notification_with_retry(subscription, payload, vapid_options, max_retries: 2)
      retries = 0

      # Validate subscription data before sending
      if subscription.endpoint.blank? || subscription.p256dh.blank? || subscription.auth.blank?
        raise StandardError, "Invalid subscription data: endpoint, p256dh, or auth is blank"
      end

      # Validate vapid options
      if vapid_options[:public_key].blank? || vapid_options[:private_key].blank? || vapid_options[:subject].blank?
        raise StandardError, "Invalid vapid options: public_key, private_key, or subject is blank"
      end

      begin
        # Standard webpush call with explicit string conversion
        Webpush.payload_send(
          message: payload,
          endpoint: subscription.endpoint.to_s,
          p256dh: subscription.p256dh.to_s,
          auth: subscription.auth.to_s,
          vapid: {
            subject: vapid_options[:subject].to_s,
            public_key: vapid_options[:public_key].to_s,
            private_key: vapid_options[:private_key].to_s,
            expiration: vapid_options[:expiration]
          }
        )
      rescue => e
        retries += 1

        # If it's the OpenSSL 3.0 immutable keys error and we haven't exceeded retries
        if e.message.include?('pkeys are immutable') && retries <= max_retries
          Rails.logger.warn "OpenSSL 3.0 key error, regenerating keys and retrying (attempt #{retries})"

          # Force regenerate keys by clearing them temporarily
          original_public = ENV['VAPID_PUBLIC_KEY']
          original_private = ENV['VAPID_PRIVATE_KEY']

          ENV['VAPID_PUBLIC_KEY'] = nil
          ENV['VAPID_PRIVATE_KEY'] = nil

          # Get new vapid options with fresh keys
          fresh_vapid_options = build_vapid_options

          # Restore original env vars
          ENV['VAPID_PUBLIC_KEY'] = original_public
          ENV['VAPID_PRIVATE_KEY'] = original_private

          # Retry with fresh keys and explicit string conversion
          Webpush.payload_send(
            message: payload,
            endpoint: subscription.endpoint.to_s,
            p256dh: subscription.p256dh.to_s,
            auth: subscription.auth.to_s,
            vapid: {
              subject: fresh_vapid_options[:subject].to_s,
              public_key: fresh_vapid_options[:public_key].to_s,
              private_key: fresh_vapid_options[:private_key].to_s,
              expiration: fresh_vapid_options[:expiration]
            }
          )
        else
          # Re-raise the original error if it's not the OpenSSL issue or we've exceeded retries
          raise e
        end
      end
    end
  end
end