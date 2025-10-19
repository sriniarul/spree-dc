module Spree
  module Admin
    class PushNotificationsController < Spree::Admin::BaseController
      def index
        @subscription_count = Spree::PushSubscription.count
        @active_subscription_count = Spree::PushSubscription.where('last_used_at > ?', 30.days.ago).count

        # Recent campaigns for quick overview
        @recent_campaigns = Spree::PushNotificationCampaign.recent.limit(5)

        # Weekly stats for mini chart
        @weekly_stats = Spree::PushNotificationCampaign.daily_stats(days: 7)
      end

      def analytics
        # Date filtering
        @start_date = params[:start_date]&.to_date || 7.days.ago.to_date
        @end_date = params[:end_date]&.to_date || Date.current

        # Ensure we don't go beyond 30 days for performance
        if (@end_date - @start_date) > 30
          @start_date = @end_date - 30.days
          flash.now[:warning] = 'Date range limited to 30 days for performance'
        end

        # Daily stats for the date range
        days_count = (@end_date - @start_date).to_i + 1
        @daily_stats = Spree::PushNotificationCampaign.daily_stats(days: days_count)

        # Filter stats by date range
        @daily_stats = @daily_stats.select do |date_key, stats|
          date = Date.parse(date_key)
          date >= @start_date && date <= @end_date
        end

        # Campaign list for the period
        @campaigns = Spree::PushNotificationCampaign
                      .for_date_range(@start_date.beginning_of_day, @end_date.end_of_day)
                      .recent
                      .limit(20)

        # Summary statistics
        @total_campaigns = @campaigns.count
        @period_stats = {
          total_sent: @campaigns.sum(:total_sent),
          total_delivered: @campaigns.sum(:total_delivered),
          total_failed: @campaigns.sum(:total_failed),
          total_clicked: @campaigns.sum(:total_clicked)
        }

        @period_stats[:success_rate] = @period_stats[:total_sent] > 0 ?
          (@period_stats[:total_delivered].to_f / @period_stats[:total_sent] * 100).round(2) : 0

        @period_stats[:click_rate] = @period_stats[:total_delivered] > 0 ?
          (@period_stats[:total_clicked].to_f / @period_stats[:total_delivered] * 100).round(2) : 0

        # Prepare data for charts (JSON format)
        @chart_data = {
          dates: @daily_stats.keys.reverse,
          sent: @daily_stats.values.reverse.map { |stat| stat[:total_sent] },
          delivered: @daily_stats.values.reverse.map { |stat| stat[:total_delivered] },
          clicked: @daily_stats.values.reverse.map { |stat| stat[:total_clicked] },
          success_rates: @daily_stats.values.reverse.map { |stat| stat[:success_rate] },
          click_rates: @daily_stats.values.reverse.map { |stat| stat[:click_rate] }
        }.to_json
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
        # Handle both nested and flat parameter structures
        if params[:push_notification].present?
          params.require(:push_notification).permit(:title, :body, :url, :icon, :badge)
        else
          # Handle flat parameters from the current form
          params.permit(:title, :body, :url, :icon, :badge).merge(
            icon: params[:icon].presence || '/icon.png',
            badge: params[:badge].presence || '/icon.png'
          )
        end
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