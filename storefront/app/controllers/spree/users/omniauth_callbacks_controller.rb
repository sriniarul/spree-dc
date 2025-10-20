module Spree
  module Users
    class OmniauthCallbacksController < Devise::OmniauthCallbacksController

      def google_oauth2
        @user = Spree.user_class.from_omniauth(request.env['omniauth.auth'])

        if @user&.persisted?
          # Sign in the user (using Devise helpers)
          sign_in(@user)
          flash[:notice] = "Welcome back, #{@user.display_name}! Successfully signed in with Google."

          # Handle popup window case
          if request.env['HTTP_REFERER']&.include?('popup') || params[:popup]
            render 'spree/oauth/popup_success', layout: false
          else
            redirect_to root_path
          end
        else
          Rails.logger.error "User validation failed: #{@user.errors.full_messages}"
          flash[:error] = 'Authentication failed. Please try again.'
          redirect_to '/users/sign_in'
        end
      end

      def failure
        Rails.logger.warn "OAuth failure: #{params[:message]}"
        flash[:error] = 'Google authentication failed. Please try again.'
        redirect_to '/users/sign_in'
      end
    end
  end
end