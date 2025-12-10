module Spree
  module SocialMedia
    class OauthInitiationController < Spree::StoreController
      before_action :authenticate_user!
      before_action :load_vendor

      def instagram
        # Store vendor ID in session for callback
        session[:vendor_id] = @vendor.id
        session[:oauth_state] = generate_state_token

        # Get Instagram App credentials from Rails credentials or ENV
        instagram_app_id = Rails.application.credentials.dig(:instagram, :app_id) ||
                          ENV['INSTAGRAM_APP_ID']
        instagram_app_secret = Rails.application.credentials.dig(:instagram, :app_secret) ||
                              ENV['INSTAGRAM_APP_SECRET']

        unless instagram_app_id.present? && instagram_app_secret.present?
          flash[:error] = 'Instagram OAuth is not configured yet. Please configure your Instagram App credentials to connect accounts.'
          redirect_to spree.admin_social_media_accounts_path
          return
        end

        # Build Instagram authorization URL
        # Using NEW Instagram API with Instagram Login (not Facebook-based)
        redirect_uri = instagram_callback_url
        state = session[:oauth_state]

        # Required scopes for Instagram Business Login
        # https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/
        scopes = %w[
          instagram_business_basic
          instagram_business_content_publish
          instagram_business_manage_messages
          instagram_business_manage_comments
        ].join(',')

        oauth_url = "https://www.instagram.com/oauth/authorize?" + {
          client_id: instagram_app_id,
          redirect_uri: redirect_uri,
          scope: scopes,
          response_type: 'code',
          state: state
        }.to_query

        Rails.logger.info "Redirecting to Instagram OAuth: #{oauth_url}"

        redirect_to oauth_url, allow_other_host: true
      end

      def facebook
        # Store vendor ID in session for callback
        session[:vendor_id] = @vendor.id
        session[:oauth_state] = generate_state_token

        # Check if Facebook OAuth is configured
        facebook_app_id = Rails.application.credentials.dig(:facebook, :app_id) ||
                         ENV['FACEBOOK_APP_ID']

        unless facebook_app_id
          flash[:error] = 'Facebook OAuth is not configured yet. Please configure your Facebook App credentials to connect accounts.'
          redirect_to spree.admin_social_media_accounts_path
          return
        end

        # Redirect to OmniAuth Facebook provider
        # The scopes are already configured in the OmniAuth initializer
        redirect_to '/auth/facebook', allow_other_host: true
      end

      def google
        # Store vendor ID in session for callback
        session[:vendor_id] = @vendor.id
        session[:platform] = params[:platform] || 'youtube'
        session[:oauth_state] = generate_state_token

        # Check if Google OAuth is configured
        google_client_id = Rails.application.credentials.dig(:google, :client_id) ||
                          ENV['GOOGLE_CLIENT_ID']

        unless google_client_id
          flash[:error] = 'Google OAuth is not configured yet. Please configure your Google OAuth credentials to connect YouTube accounts.'
          redirect_to spree.admin_social_media_accounts_path
          return
        end

        # Redirect to OmniAuth Google provider
        # The scopes are already configured in the OmniAuth initializer
        redirect_to '/auth/google_oauth2', allow_other_host: true
      end

      def tiktok
        # Store vendor ID in session for callback
        session[:vendor_id] = @vendor.id

        # Build TikTok OAuth URL
        scopes = %w[
          user.info.basic
          video.list
          video.upload
          user.info.profile
        ]

        tiktok_client_key = Rails.application.credentials.dig(:tiktok, :client_key) ||
                           ENV['TIKTOK_CLIENT_KEY']

        unless tiktok_client_key
          flash[:error] = 'TikTok OAuth is not configured yet. Please configure your TikTok Business API credentials to connect accounts.'
          redirect_to spree.admin_social_media_accounts_path
          return
        end

        oauth_url = "https://www.tiktok.com/v2/auth/authorize?" + {
          client_key: tiktok_client_key,
          redirect_uri: oauth_callback_url('tiktok'),
          scope: scopes.join(','),
          response_type: 'code',
          state: generate_state_token
        }.to_query

        redirect_to oauth_url, allow_other_host: true
      end

      def twitter
        # Twitter/X OAuth implementation would go here
        flash[:info] = 'Twitter/X integration coming soon!'
        redirect_to spree.admin_social_media_accounts_path
      end

      private

      def authenticate_user!
        # Use Spree's authentication
        unless spree_current_user
          flash[:error] = 'Please sign in to connect social media accounts.'
          redirect_to spree.login_path
        end
      end

      def load_vendor
        vendor_id = params[:vendor_id] || session[:vendor_id]

        @vendor = if vendor_id.present?
                    Spree::Vendor.find(vendor_id)
                  elsif spree_current_user&.vendor
                    spree_current_user.vendor
                  else
                    # For non-vendor users (admins), try to get vendor from params or use first vendor
                    vendor_id.present? ? Spree::Vendor.find(vendor_id) : Spree::Vendor.first
                  end

        unless @vendor
          flash[:error] = 'No vendor account found. Please contact support.'
          redirect_to spree.admin_social_media_accounts_path
        end
      end

      def oauth_callback_url(provider)
        # Use the main application's callback URL
        "#{request.protocol}#{request.host_with_port}/auth/#{provider}/callback"
      end

      def instagram_callback_url
        # Instagram-specific callback URL
        "#{request.protocol}#{request.host_with_port}/social_media/oauth/instagram/callback"
      end

      def generate_state_token
        # Generate a secure random state token for CSRF protection
        state_token = SecureRandom.hex(32)
        session[:oauth_state_token] = state_token
        state_token
      end
    end
  end
end