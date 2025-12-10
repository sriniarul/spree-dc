module Spree
  module Admin
    class SocialMediaController < Spree::Admin::BaseController
      before_action :load_vendor
      before_action :authorize_social_media_access
      before_action :load_social_media_accounts, only: [:index]
      before_action :load_recent_posts, only: [:index]
      before_action :load_analytics_summary, only: [:index]

      def index
        # Stats for overview cards
        @connected_accounts_count = @social_media_accounts.active.count
        @posts_this_month = Spree::SocialMediaPost.by_vendor(@vendor.id)
                                                   .where(created_at: Date.current.beginning_of_month..Date.current.end_of_month)
                                                   .count
        @scheduled_posts_count = Spree::SocialMediaPost.by_vendor(@vendor.id).scheduled.count
        @total_engagement = @analytics_summary[:total_engagement] || 0
      end

      private

      def load_vendor
        # Simplified vendor loading - use current_vendor if available, otherwise use first vendor
        @vendor = current_vendor || Spree::Vendor.first

        Rails.logger.info "Social Media Controller - Vendor loaded: #{@vendor.inspect}"

        unless @vendor
          flash[:error] = Spree.t(:no_vendor_associated, default: 'No vendor is associated with this account.')
          redirect_to spree.admin_root_path
        end
      end

      def load_social_media_accounts
        @facebook_connection = @vendor.social_media_accounts.facebook_accounts.active.first
        @instagram_connection = @vendor.social_media_accounts.instagram_accounts.active.first
        @whatsapp_connection = @vendor.social_media_accounts.whatsapp_accounts.active.first
        @youtube_connection = @vendor.social_media_accounts.youtube_accounts.active.first
        @tiktok_connection = @vendor.social_media_accounts.tiktok_accounts.active.first

        @social_media_accounts = @vendor.social_media_accounts.includes(:social_media_analytics)
      end

      def load_recent_posts
        @recent_posts = Spree::SocialMediaPost.by_vendor(@vendor.id)
                                            .includes(:social_media_account, :product)
                                            .recent
                                            .limit(10)
      end

      def authorize_social_media_access
        authorize! :read, :social_media_dashboard
      end

      def load_analytics_summary
        @analytics_summary = {
          total_impressions: 0,
          total_engagement: 0,
          top_performing_platform: nil,
          engagement_rate: 0
        }

        # Only load analytics if the model exists and there are accounts
        return unless defined?(Spree::SocialMediaAnalytics) && @social_media_accounts&.any?

        begin
          # Calculate summary analytics
          analytics = Spree::SocialMediaAnalytics.joins(:social_media_account)
                                                .where(spree_social_media_accounts: { vendor_id: @vendor.id })
                                                .where(date: 30.days.ago..Date.current)

          if analytics.any?
            @analytics_summary[:total_impressions] = analytics.sum(:impressions)
            @analytics_summary[:total_engagement] = analytics.sum(:likes) + analytics.sum(:comments) + analytics.sum(:shares)

            if @analytics_summary[:total_impressions] > 0
              @analytics_summary[:engagement_rate] = ((@analytics_summary[:total_engagement].to_f / @analytics_summary[:total_impressions]) * 100).round(2)
            end

            # Find top performing platform
            platform_performance = analytics.joins(:social_media_account)
                                          .group('spree_social_media_accounts.platform')
                                          .sum(:impressions)
            @analytics_summary[:top_performing_platform] = platform_performance.max_by { |k, v| v }&.first
          end
        rescue => e
          Rails.logger.error "Error loading social media analytics: #{e.message}"
          # Keep default values if there's an error
        end
      end

      def calculate_total_reach
        @social_media_accounts.active.sum do |account|
          account.latest_analytics&.impressions || 0
        end
      end

      # Helper method for multivendor compatibility
      def current_vendor
        # This method should be implemented based on your multivendor setup
        # It might come from a concern or be set in application controller
        super if defined?(super)
      end
    end
  end
end