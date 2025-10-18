module Spree
  class PushSubscription < Spree.base_class
    belongs_to :user, class_name: Spree.user_class.name, optional: true

    validates :endpoint, presence: true, uniqueness: true
    validates :p256dh, presence: true
    validates :auth, presence: true

    scope :active, -> { where('last_used_at > ?', 6.months.ago) }
    scope :inactive, -> { where('last_used_at <= ?', 6.months.ago) }

    def self.create_or_update_from_json(subscription_json, user_id = nil)
      # Handle potential errors with invalid JSON
      begin
        subscription_hash = subscription_json.is_a?(String) ? JSON.parse(subscription_json) : subscription_json
      rescue JSON::ParserError => e
        Rails.logger.error("Invalid subscription JSON: #{e.message}")
        return nil
      end

      # Extract required values
      endpoint = subscription_hash['endpoint']

      if endpoint.blank?
        Rails.logger.error("Missing endpoint in subscription")
        return nil
      end

      keys = subscription_hash.dig('keys') || {}
      p256dh = keys['p256dh']
      auth = keys['auth']

      if p256dh.blank? || auth.blank?
        Rails.logger.error("Missing p256dh or auth keys in subscription")
        return nil
      end

      # Find existing or create new
      subscription = find_by(endpoint: endpoint) || new
      subscription.endpoint = endpoint
      subscription.p256dh = p256dh
      subscription.auth = auth
      subscription.user_id = user_id if user_id.present?
      subscription.last_used_at = Time.current

      # Save with error handling
      begin
        subscription.save
        subscription
      rescue => e
        Rails.logger.error("Error saving subscription: #{e.message}")
        nil
      end
    end
  end
end