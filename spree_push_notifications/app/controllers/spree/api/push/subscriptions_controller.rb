module Spree
  module Api
    module Push
      class SubscriptionsController < ::ApplicationController
        skip_before_action :verify_authenticity_token, only: [:create]

        def public_key
          render json: { publicKey: ENV['VAPID_PUBLIC_KEY'] }
        end

        def create
          user_id = spree_current_user&.id

          subscription = Spree::PushSubscription.create_or_update_from_json(
            params[:subscription],
            user_id
          )

          if subscription&.persisted?
            render json: { success: true, id: subscription.id }
          else
            render json: { success: false, error: "Invalid subscription data" }, status: :unprocessable_entity
          end
        end

        def test
          if params[:endpoint].blank? || params[:p256dh].blank? || params[:auth].blank?
            return render json: { success: false, error: "Missing required parameters" }, status: :bad_request
          end

          subscription = Spree::PushSubscription.new(
            endpoint: params[:endpoint],
            p256dh: params[:p256dh],
            auth: params[:auth],
            last_used_at: Time.current
          )

          result = Spree::PushNotificationService.send_to_subscription(
            subscription,
            "Spree Test",
            params[:message] || "This is a test push notification",
            { url: params[:url] || "/" }
          )

          render json: { success: result[:success] > 0, result: result }
        end
      end
    end
  end
end