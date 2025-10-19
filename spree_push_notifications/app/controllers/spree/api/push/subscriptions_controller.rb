module Spree
  module Api
    module Push
      class SubscriptionsController < ::ApplicationController
        skip_before_action :verify_authenticity_token, only: [:create]

        def public_key
          # Use the same VAPID options method as the service to ensure consistency
          vapid_options = Spree::PushNotificationService.send(:build_vapid_options)
          render json: { publicKey: vapid_options[:public_key] }
        end

        def create
          user_id = spree_current_user&.id
          subscription_params = params[:subscription]

          # Handle both old and new formats for backward compatibility
          if subscription_params[:endpoint].present?
            # New format from updated JavaScript
            subscription = Spree::PushSubscription.find_or_initialize_by(
              endpoint: subscription_params[:endpoint]
            )

            subscription.assign_attributes(
              user_id: user_id,
              p256dh: subscription_params[:p256dh],
              auth: subscription_params[:auth],
              last_used_at: Time.current
            )
          else
            # Old format for backward compatibility
            subscription = Spree::PushSubscription.create_or_update_from_json(
              subscription_params,
              user_id
            )
          end

          if subscription&.save
            render json: { success: true, id: subscription.id }
          else
            render json: {
              success: false,
              error: subscription&.errors&.full_messages&.join(', ') || "Invalid subscription data"
            }, status: :unprocessable_entity
          end
        end

        def unsubscribe
          if params[:subscription].present?
            subscription_data = params[:subscription]
            endpoint = subscription_data[:endpoint]

            if endpoint.present?
              subscription = Spree::PushSubscription.find_by(endpoint: endpoint)
              if subscription
                subscription.destroy
                render json: { success: true, message: "Successfully unsubscribed" }
              else
                render json: { success: false, error: "Subscription not found" }, status: :not_found
              end
            else
              render json: { success: false, error: "Missing endpoint" }, status: :bad_request
            end
          else
            render json: { success: false, error: "Missing subscription data" }, status: :bad_request
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