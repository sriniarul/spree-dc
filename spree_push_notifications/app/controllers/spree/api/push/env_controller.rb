module Spree
  module Api
    module Push
      class EnvController < Spree::Api::BaseController
        def show
          render json: {
            vapidPublicKey: vapid_public_key
          }
        end

        private

        def vapid_public_key
          Rails.application.credentials.vapid&.dig(:public_key) ||
            ENV['VAPID_PUBLIC_KEY'] ||
            Spree::PushNotificationService.generate_vapid_keys[:public_key]
        end
      end
    end
  end
end