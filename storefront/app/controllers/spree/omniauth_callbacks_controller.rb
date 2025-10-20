module Spree
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    include Spree::Core::ControllerHelpers::Store
    include Spree::Core::ControllerHelpers::Order

    def google_oauth2
      @user = Spree.user_class.from_omniauth(request.env["omniauth.auth"])

      if @user.persisted?
        flash[:notice] = I18n.t 'devise.omniauth_callbacks.success', kind: 'Google'
        sign_in_and_redirect @user, event: :authentication
      else
        session["devise.google_data"] = request.env["omniauth.auth"].except("extra")
        redirect_to new_user_registration_url, alert: @user.errors.full_messages.join("\n")
      end
    end

    def failure
      flash[:alert] = I18n.t 'devise.omniauth_callbacks.failure', kind: OmniAuth::Utils.camelize(failed_strategy.name), reason: failure_message
      redirect_to new_user_session_path
    end

    private

    def after_omniauth_failure_path_for(scope)
      new_user_session_path
    end
  end
end