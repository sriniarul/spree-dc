module Spree
  module UserOauth
    extend ActiveSupport::Concern

    included do
      # Add OAuth fields to User model
      # These will be added via migration
      # - provider: string (e.g., 'google_oauth2')
      # - uid: string (unique identifier from OAuth provider)
      # - first_name: string (from OAuth provider)
      # - last_name: string (from OAuth provider)
      # - image_url: string (avatar from OAuth provider)

      validates :uid, uniqueness: { scope: :provider }, allow_blank: true
    end

    class_methods do
      # Find or create user from OAuth data
      def from_omniauth(auth)
        # First, try to find existing user by provider and uid
        user = find_by(provider: auth.provider, uid: auth.uid)

        return user if user.present?

        # Next, try to find existing user by email (for account linking)
        user = find_by(email: auth.info.email)

        if user.present?
          # Link existing account with OAuth
          user.update!(
            provider: auth.provider,
            uid: auth.uid,
            first_name: auth.info.first_name || user.first_name,
            last_name: auth.info.last_name || user.last_name,
            image_url: auth.info.image
          )
          return user
        end

        # Create new user from OAuth data
        user = create!(
          email: auth.info.email,
          password: Devise.friendly_token[0, 20],
          provider: auth.provider,
          uid: auth.uid,
          first_name: auth.info.first_name,
          last_name: auth.info.last_name,
          image_url: auth.info.image,
          confirmed_at: Time.current # Auto-confirm OAuth users
        )

        user
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error "OAuth user creation failed: #{e.message}"
        nil
      end
    end

    # Check if user is OAuth user
    def oauth_user?
      provider.present? && uid.present?
    end

    # Get display name for OAuth user
    def oauth_display_name
      if first_name.present? && last_name.present?
        "#{first_name} #{last_name}"
      elsif first_name.present?
        first_name
      else
        email
      end
    end

    # Check if user has a linked regular password
    def has_password?
      encrypted_password.present? && !oauth_user?
    end
  end
end