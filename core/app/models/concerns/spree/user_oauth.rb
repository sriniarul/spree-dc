module Spree
  module UserOauth
    extend ActiveSupport::Concern

    included do
      # Only add omniauthable if devise is available and not already configured
      if respond_to?(:devise)
        begin
          # Check if omniauthable is already configured
          unless respond_to?(:devise_modules) && devise_modules&.include?(:omniauthable)
            devise :omniauthable, omniauth_providers: [:google_oauth2]
          end
        rescue
          # Fallback: try to add omniauthable anyway
          devise :omniauthable, omniauth_providers: [:google_oauth2] rescue nil
        end
      end
    end

    class_methods do
      def from_omniauth(auth)
        # First try to find user by provider and uid
        user = find_by(provider: auth.provider, uid: auth.uid)

        if user.present?
          # Update user info from OAuth if found
          user.update(
            first_name: auth.info.first_name,
            last_name: auth.info.last_name,
            image_url: auth.info.image
          )
          return user
        end

        # Try to find existing user by email
        email = auth.info.email
        user = find_by(email: email) if email.present?

        if user.present?
          # Link OAuth account to existing user
          user.update(
            provider: auth.provider,
            uid: auth.uid,
            first_name: auth.info.first_name || user.first_name,
            last_name: auth.info.last_name || user.last_name,
            image_url: auth.info.image
          )
          return user
        end

        # Create new user from OAuth data
        if email.present?
          user = create(
            email: email,
            provider: auth.provider,
            uid: auth.uid,
            first_name: auth.info.first_name,
            last_name: auth.info.last_name,
            image_url: auth.info.image,
            password: SecureRandom.hex(16) # Generate secure random password
          )
          return user
        end

        nil
      end
    end

    def oauth_user?
      provider.present? && uid.present?
    end

    def full_name
      if first_name.present? || last_name.present?
        [first_name, last_name].compact.join(' ')
      else
        email
      end
    end
  end
end