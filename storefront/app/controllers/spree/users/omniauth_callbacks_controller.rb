module Spree
  module Users
    class OmniauthCallbacksController < Devise::OmniauthCallbacksController
      include Spree::Storefront::DeviseConcern

      # Google OAuth callback
      def google_oauth2
        process_oauth_callback
      end

      # Handle OAuth failures
      def failure
        Rails.logger.error "OAuth failure: #{params[:message] || 'Unknown error'}"

        flash[:error] = I18n.t('spree.oauth.login_failed',
                              message: params[:message] || I18n.t('spree.oauth.unknown_error'))
        redirect_to spree.login_path
      end

      private

      def process_oauth_callback
        @user = Spree.user_class.from_omniauth(request.env['omniauth.auth'])

        if @user&.persisted?
          handle_successful_oauth
        else
          handle_failed_oauth
        end
      end

      def handle_successful_oauth
        # Set flash message based on whether this is a new user or existing
        if @user.oauth_user? && @user.created_at > 1.minute.ago
          flash[:notice] = I18n.t('spree.oauth.account_created_successfully',
                                 provider: provider_name)
        else
          flash[:notice] = I18n.t('spree.oauth.signed_in_successfully',
                                 provider: provider_name)
        end

        sign_in_and_redirect @user, event: :authentication
        set_flash_message(:notice, :success, kind: provider_name) if is_navigational_format?
      end

      def handle_failed_oauth
        Rails.logger.error "OAuth user creation failed for #{request.env['omniauth.auth']&.info&.email}"

        # Store OAuth data in session for potential manual signup
        session["devise.#{provider_key}_data"] = request.env['omniauth.auth'].except('extra')

        flash[:error] = I18n.t('spree.oauth.account_creation_failed')
        redirect_to spree.new_spree_user_registration_path
      end

      def provider_name
        action_name.humanize.titleize
      end

      def provider_key
        action_name
      end
    end
  end
end