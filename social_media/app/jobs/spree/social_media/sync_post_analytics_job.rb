module Spree
  module SocialMedia
    class SyncPostAnalyticsJob < ApplicationJob
      queue_as :social_media_analytics

      retry_on StandardError, wait: :exponentially_longer, attempts: 3

      def perform(post_id, insights_data = nil)
        @post = Spree::SocialMediaPost.find(post_id)
        @account = @post.social_media_account

        Rails.logger.info "Syncing analytics for post #{post_id} (#{@post.platform_post_id})"

        begin
          # Use provided insights data or fetch from API
          if insights_data
            process_insights_data(insights_data)
          else
            fetch_and_process_insights
          end

          # Update post engagement metrics
          calculate_engagement_metrics

          # Check for performance milestones
          check_post_milestones

          # Update sync timestamp
          @post.update!(analytics_synced_at: Time.current)

          Rails.logger.info "Successfully synced analytics for post #{post_id}"

        rescue => e
          Rails.logger.error "Failed to sync post analytics #{post_id}: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          raise
        end
      end

      private

      def fetch_and_process_insights
        service = Spree::SocialMedia::InstagramApiService.new(@account.access_token)

        insights_data = service.get_media_insights(
          @post.platform_post_id,
          metrics: determine_metrics_for_content_type
        )

        if insights_data[:success]
          process_insights_data(insights_data[:data])
        else
          Rails.logger.error "Failed to fetch insights: #{insights_data[:error]}"
        end
      end

      def process_insights_data(insights)
        # Create or update analytics record
        analytics = @post.social_media_analytics.find_or_create_by(
          date: @post.published_at&.to_date || Date.current
        )

        # Process different metrics based on content type
        case @post.content_type
        when 'post', 'carousel'
          process_post_insights(analytics, insights)
        when 'reel', 'video'
          process_reel_insights(analytics, insights)
        when 'story'
          process_story_insights(analytics, insights)
        end

        # Common metrics for all content types
        analytics.update!(
          raw_data: insights.to_json,
          synced_at: Time.current
        )

        Rails.logger.info "Processed insights for #{@post.content_type}: #{analytics.engagement}"
      end

      def process_post_insights(analytics, insights)
        metrics = extract_metrics_from_insights(insights)

        analytics.update!(
          impressions: metrics['impressions'] || 0,
          reach: metrics['reach'] || 0,
          likes: metrics['likes'] || @post.likes_count || 0,
          comments: metrics['comments'] || @post.comments_count || 0,
          shares: metrics['shares'] || @post.shares_count || 0,
          saves: metrics['saves'] || @post.saves_count || 0,
          profile_visits: metrics['profile_visits'] || 0,
          website_clicks: metrics['website_clicks'] || 0,
          engagement: calculate_total_engagement(metrics)
        )

        # Update post counters
        @post.update!(
          likes_count: metrics['likes'] || @post.likes_count || 0,
          comments_count: metrics['comments'] || @post.comments_count || 0,
          shares_count: metrics['shares'] || @post.shares_count || 0,
          saves_count: metrics['saves'] || @post.saves_count || 0,
          impressions: metrics['impressions'] || 0,
          reach: metrics['reach'] || 0
        )
      end

      def extract_metrics_from_insights(insights)
        metrics = {}

        if insights.is_a?(Array)
          # Instagram API returns array of insight objects
          insights.each do |insight|
            metric_name = insight['name']
            metric_value = insight.dig('values', 0, 'value') || 0
            metrics[metric_name] = metric_value
          end
        elsif insights.is_a?(Hash)
          # Direct hash of metrics
          metrics = insights
        end

        metrics
      end

      def calculate_total_engagement(metrics)
        likes = metrics['likes'] || 0
        comments = metrics['comments'] || 0
        shares = metrics['shares'] || 0
        saves = metrics['saves'] || 0

        likes + comments + shares + saves
      end

      def calculate_engagement_metrics
        return unless @post.impressions && @post.impressions > 0

        # Calculate engagement rate
        total_engagement = (@post.likes_count || 0) +
                          (@post.comments_count || 0) +
                          (@post.shares_count || 0) +
                          (@post.saves_count || 0)

        engagement_rate = (total_engagement.to_f / @post.impressions * 100).round(2)

        # Update post engagement rate
        @post.update!(engagement_rate: engagement_rate)

        Rails.logger.info "Calculated engagement rate: #{engagement_rate}% for post #{@post.id}"
      end

      def check_post_milestones
        # Check for various performance milestones
        check_likes_milestones
        check_reach_milestones
      end

      def check_likes_milestones
        likes_count = @post.likes_count || 0
        milestone_thresholds = [100, 500, 1000, 5000, 10000]

        milestone_thresholds.each do |threshold|
          if likes_count >= threshold
            create_milestone_if_new("likes_#{threshold}", "Post reached #{threshold} likes!")
          end
        end
      end

      def check_reach_milestones
        reach = @post.reach || 0
        if reach >= 10000
          create_milestone_if_new('reach_10k', 'Post reached 10K people!')
        end
      end

      def create_milestone_if_new(milestone_type, message)
        existing_milestone = Spree::SocialMediaMilestone.find_by(
          social_media_post: @post,
          milestone_type: milestone_type
        )

        return if existing_milestone

        Spree::SocialMediaMilestone.create!(
          social_media_account: @account,
          social_media_post: @post,
          milestone_type: milestone_type,
          message: message,
          achieved_at: Time.current,
          metrics_data: {
            likes_count: @post.likes_count,
            comments_count: @post.comments_count,
            reach: @post.reach
          }.to_json
        )

        Rails.logger.info "Created milestone: #{milestone_type} for post #{@post.id}"
      end

      def determine_metrics_for_content_type
        case @post.content_type
        when 'story'
          %w[impressions reach exits replies taps_forward taps_back]
        when 'reel', 'video'
          %w[impressions reach likes comments shares saves video_views plays]
        else
          %w[impressions reach likes comments shares saves profile_visits website_clicks]
        end
      end
    end
  end
end