module Spree
  module Admin
    module SocialMediaNavigationHelper
      # Check if social media navigation should be shown
      def show_social_media_nav?
        return false unless respond_to?(:current_vendor) && current_vendor&.approved?

        # Check if user has permission to manage social media
        can?(:manage, Spree::SocialMediaAccount) || can?(:manage, Spree::SocialMediaPost)
      end

      # Get social media navigation active state
      def social_media_nav_active?
        controller_name.start_with?('social_media') ||
          (controller_name == 'social_media' ||
           %w[accounts posts campaigns analytics].include?(controller_name) && params[:controller]&.include?('social_media'))
      end

      # Get social media platform icon
      def platform_icon(platform)
        case platform
        when 'facebook'
          'brand-facebook'
        when 'instagram'
          'brand-instagram'
        when 'whatsapp'
          'brand-whatsapp'
        when 'youtube'
          'brand-youtube'
        when 'tiktok'
          'brand-tiktok'
        else
          'link'
        end
      end

      # Get platform badge color
      def platform_badge_color(platform, status)
        return 'secondary' unless status == 'active'

        case platform
        when 'facebook'
          'primary'
        when 'instagram'
          'danger'
        when 'whatsapp'
          'success'
        when 'youtube'
          'warning'
        when 'tiktok'
          'dark'
        else
          'info'
        end
      end

      # Format social media metrics
      def format_social_metric(value)
        return '0' unless value && value > 0

        if value >= 1_000_000
          "#{(value / 1_000_000.0).round(1)}M"
        elsif value >= 1_000
          "#{(value / 1_000.0).round(1)}K"
        else
          value.to_s
        end
      end

      # Check if vendor has any social media accounts
      def vendor_has_social_accounts?
        return false unless current_vendor

        current_vendor.social_media_accounts.active.any?
      end

      # Get vendor's connected platforms
      def vendor_connected_platforms
        return [] unless current_vendor

        current_vendor.social_media_accounts.active.pluck(:platform).uniq
      end

      # Check if platform is connected
      def platform_connected?(platform)
        return false unless current_vendor

        current_vendor.social_media_accounts.active.where(platform: platform).exists?
      end

      # Get social media dashboard summary
      def social_media_dashboard_summary
        return {} unless current_vendor

        {
          total_accounts: current_vendor.social_media_accounts.active.count,
          scheduled_posts: current_vendor.social_media_posts.scheduled.count,
          posts_today: current_vendor.social_media_posts.where(created_at: Date.current.beginning_of_day..Date.current.end_of_day).count,
          total_reach: calculate_vendor_reach
        }
      end

      private

      def calculate_vendor_reach
        return 0 unless current_vendor

        current_vendor.social_media_accounts.active.sum(:followers_count)
      end
    end
  end
end