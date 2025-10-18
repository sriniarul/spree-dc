module Spree
  module Admin
    class PushNotificationsController < Spree::Admin::BaseController
      def index
        @subscription_count = Spree::PushSubscription.count
        @active_subscription_count = Spree::PushSubscription.where('last_used_at > ?', 30.days.ago).count
      end

      def new
        @push_notification = OpenStruct.new(
          title: '',
          body: '',
          url: '/',
          icon: '/icon.png',
          badge: '/icon.png'
        )
      end

      def create
        @push_notification = OpenStruct.new(push_notification_params)

        if validate_notification_params
          # Queue the bulk notification job
          Spree::BulkPushNotificationJob.perform_later(
            @push_notification.title,
            @push_notification.body,
            {
              url: @push_notification.url,
              icon: @push_notification.icon,
              badge: @push_notification.badge
            }
          )

          flash[:success] = Spree.t('admin.push_notifications.successfully_queued')
          redirect_to spree.admin_push_notifications_path
        else
          flash.now[:error] = Spree.t('admin.push_notifications.validation_failed')
          render :new
        end
      end

      def test
        subscription_count = Spree::PushSubscription.where('last_used_at > ?', 30.days.ago).count

        if subscription_count == 0
          flash[:warning] = Spree.t('admin.push_notifications.no_active_subscriptions')
        else
          # Send test notification
          Spree::BulkPushNotificationJob.perform_later(
            'Test Notification',
            'This is a test push notification from the admin panel',
            { url: '/' }
          )

          flash[:success] = Spree.t('admin.push_notifications.test_queued', count: subscription_count)
        end

        redirect_to spree.admin_push_notifications_path
      end

      private

      def push_notification_params
        params.require(:push_notification).permit(:title, :body, :url, :icon, :badge)
      end

      def validate_notification_params
        errors = []
        errors << 'Title is required' if @push_notification.title.blank?
        errors << 'Body is required' if @push_notification.body.blank?
        errors << 'URL must be valid' if @push_notification.url.blank?

        if errors.any?
          @push_notification.errors = errors
          false
        else
          true
        end
      end
    end
  end
end