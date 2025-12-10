module Spree
  module SocialMedia
    class InstagramAnalyticsService
      BASE_URL = 'https://graph.facebook.com/v18.0'

      def initialize(social_media_account)
        @account = social_media_account
        @access_token = @account.access_token
        @instagram_business_account_id = @account.platform_user_id
      end

      def get_account_insights(date_range = 7.days.ago..Date.current, period = 'day')
        metrics = %w[
          impressions
          reach
          profile_views
          website_clicks
          follower_count
        ]

        since_timestamp = date_range.begin.to_time.to_i
        until_timestamp = date_range.end.to_time.to_i

        response = HTTParty.get("#{BASE_URL}/#{@instagram_business_account_id}/insights",
          query: {
            metric: metrics.join(','),
            period: period,
            since: since_timestamp,
            until: until_timestamp,
            access_token: @access_token
          }
        )

        handle_response(response)
      end

      def get_media_insights(media_id, metrics = nil)
        # Default metrics for different media types
        default_metrics = %w[
          impressions
          reach
          engagement
          likes
          comments
          shares
          saves
        ]

        metrics ||= default_metrics

        response = HTTParty.get("#{BASE_URL}/#{media_id}/insights",
          query: {
            metric: metrics.join(','),
            access_token: @access_token
          }
        )

        handle_response(response)
      end

      def get_story_insights(story_id)
        story_metrics = %w[
          impressions
          reach
          replies
          taps_forward
          taps_back
          exits
        ]

        response = HTTParty.get("#{BASE_URL}/#{story_id}/insights",
          query: {
            metric: story_metrics.join(','),
            access_token: @access_token
          }
        )

        handle_response(response)
      end

      def get_audience_insights(date_range = 30.days.ago..Date.current)
        audience_metrics = %w[
          audience_gender_age
          audience_locale
          audience_country
          audience_city
        ]

        since_timestamp = date_range.begin.to_time.to_i
        until_timestamp = date_range.end.to_time.to_i

        response = HTTParty.get("#{BASE_URL}/#{@instagram_business_account_id}/insights",
          query: {
            metric: audience_metrics.join(','),
            period: 'lifetime',
            since: since_timestamp,
            until: until_timestamp,
            access_token: @access_token
          }
        )

        handle_response(response)
      end

      def get_hashtag_performance(hashtag_name, limit = 20)
        # Search for hashtag
        hashtag_response = HTTParty.get("#{BASE_URL}/ig_hashtag_search",
          query: {
            user_id: @instagram_business_account_id,
            q: hashtag_name,
            access_token: @access_token
          }
        )

        hashtag_data = handle_response(hashtag_response)
        return {} unless hashtag_data['data']&.any?

        hashtag_id = hashtag_data['data'].first['id']

        # Get hashtag insights
        insights_response = HTTParty.get("#{BASE_URL}/#{hashtag_id}",
          query: {
            fields: 'id,name,media_count',
            access_token: @access_token
          }
        )

        # Get recent media using this hashtag
        recent_media_response = HTTParty.get("#{BASE_URL}/#{hashtag_id}/recent_media",
          query: {
            user_id: @instagram_business_account_id,
            fields: 'id,media_type,like_count,comments_count,timestamp,permalink',
            limit: limit,
            access_token: @access_token
          }
        )

        {
          hashtag_info: handle_response(insights_response),
          recent_media: handle_response(recent_media_response)
        }
      rescue => e
        Rails.logger.error "Hashtag performance error: #{e.message}"
        {}
      end

      def get_competitor_analysis(competitor_usernames = [])
        # Note: This requires additional permissions and may not be available for all accounts
        competitor_data = []

        competitor_usernames.each do |username|
          begin
            # Search for user (limited data available)
            user_response = HTTParty.get("#{BASE_URL}/ig_user_search",
              query: {
                q: username,
                access_token: @access_token
              }
            )

            user_data = handle_response(user_response)
            competitor_data << {
              username: username,
              data: user_data['data']&.first || {}
            }
          rescue => e
            Rails.logger.warn "Could not fetch competitor data for #{username}: #{e.message}"
          end
        end

        competitor_data
      end

      def calculate_engagement_metrics(insights_data)
        return {} if insights_data.blank?

        metrics = {}

        insights_data.each do |insight|
          metric_name = insight['name']
          values = insight['values'] || []

          case metric_name
          when 'impressions'
            metrics[:total_impressions] = values.sum { |v| v['value'].to_i }
          when 'reach'
            metrics[:total_reach] = values.sum { |v| v['value'].to_i }
          when 'engagement'
            metrics[:total_engagement] = values.sum { |v| v['value'].to_i }
          when 'follower_count'
            metrics[:current_followers] = values.last&.dig('value').to_i
          when 'profile_views'
            metrics[:total_profile_views] = values.sum { |v| v['value'].to_i }
          end
        end

        # Calculate derived metrics
        if metrics[:total_engagement] && metrics[:total_reach] && metrics[:total_reach] > 0
          metrics[:engagement_rate] = (metrics[:total_engagement].to_f / metrics[:total_reach] * 100).round(2)
        end

        if metrics[:total_reach] && metrics[:total_impressions] && metrics[:total_impressions] > 0
          metrics[:reach_rate] = (metrics[:total_reach].to_f / metrics[:total_impressions] * 100).round(2)
        end

        metrics
      end

      def sync_post_analytics(social_media_post)
        return false unless social_media_post.platform_post_id

        begin
          # Get media insights for this post
          insights = get_media_insights(social_media_post.platform_post_id)

          if insights['data'].present?
            analytics_data = extract_post_analytics(insights['data'])

            # Update post with analytics
            social_media_post.update!(
              engagement_count: analytics_data[:engagement_count],
              impressions_count: analytics_data[:impressions_count],
              reach_count: analytics_data[:reach_count],
              analytics_synced_at: Time.current,
              analytics_data: analytics_data
            )

            # Create analytics record
            Spree::SocialMediaAnalytics.create!(
              social_media_account: @account,
              social_media_post: social_media_post,
              date: social_media_post.published_at.to_date,
              impressions: analytics_data[:impressions_count],
              reach: analytics_data[:reach_count],
              engagement: analytics_data[:engagement_count],
              likes: analytics_data[:likes_count],
              comments: analytics_data[:comments_count],
              shares: analytics_data[:shares_count],
              saves: analytics_data[:saves_count],
              profile_visits: analytics_data[:profile_visits_count],
              website_clicks: analytics_data[:website_clicks_count],
              raw_data: insights
            )

            true
          else
            false
          end
        rescue => e
          Rails.logger.error "Failed to sync analytics for post #{social_media_post.id}: #{e.message}"
          false
        end
      end

      def generate_analytics_report(date_range = 30.days.ago..Date.current, format = :summary)
        account_insights = get_account_insights(date_range)
        account_metrics = calculate_engagement_metrics(account_insights['data'] || [])

        # Get post performance data
        posts_in_range = @account.social_media_posts
                                .published
                                .where(published_at: date_range)
                                .includes(:social_media_analytics)

        post_metrics = calculate_post_metrics(posts_in_range)

        case format
        when :detailed
          generate_detailed_report(account_metrics, post_metrics, date_range)
        when :summary
          generate_summary_report(account_metrics, post_metrics, date_range)
        when :export
          generate_export_data(account_metrics, post_metrics, date_range)
        else
          generate_summary_report(account_metrics, post_metrics, date_range)
        end
      end

      def get_best_performing_content(limit = 10, metric = 'engagement_rate')
        posts = @account.social_media_posts
                       .published
                       .joins(:social_media_analytics)
                       .includes(:social_media_analytics)

        case metric
        when 'engagement_rate'
          posts = posts.order('(spree_social_media_analytics.engagement::float / NULLIF(spree_social_media_analytics.reach, 0)) DESC')
        when 'reach'
          posts = posts.order('spree_social_media_analytics.reach DESC')
        when 'impressions'
          posts = posts.order('spree_social_media_analytics.impressions DESC')
        when 'engagement'
          posts = posts.order('spree_social_media_analytics.engagement DESC')
        end

        posts.limit(limit).map do |post|
          analytics = post.social_media_analytics.first

          {
            post_id: post.id,
            caption: post.caption.truncate(100),
            published_at: post.published_at,
            content_type: post.content_type,
            platform_url: post.platform_url,
            metrics: {
              impressions: analytics&.impressions || 0,
              reach: analytics&.reach || 0,
              engagement: analytics&.engagement || 0,
              likes: analytics&.likes || 0,
              comments: analytics&.comments || 0,
              shares: analytics&.shares || 0,
              saves: analytics&.saves || 0,
              engagement_rate: analytics ? calculate_engagement_rate(analytics) : 0
            }
          }
        end
      end

      def get_posting_insights(date_range = 30.days.ago..Date.current)
        posts = @account.social_media_posts
                       .published
                       .where(published_at: date_range)
                       .joins(:social_media_analytics)

        insights = {
          total_posts: posts.count,
          posting_frequency: {},
          best_performing_times: {},
          content_type_performance: {},
          hashtag_performance: {}
        }

        # Analyze posting frequency
        posts.group("DATE(published_at)").count.each do |date, count|
          day_name = Date.parse(date.to_s).strftime('%A')
          insights[:posting_frequency][day_name] ||= []
          insights[:posting_frequency][day_name] << count
        end

        # Average by day of week
        insights[:posting_frequency].each do |day, counts|
          insights[:posting_frequency][day] = counts.sum.to_f / counts.size
        end

        # Analyze best performing times
        posts.each do |post|
          hour = post.published_at.hour
          analytics = post.social_media_analytics.first
          engagement_rate = analytics ? calculate_engagement_rate(analytics) : 0

          insights[:best_performing_times][hour] ||= []
          insights[:best_performing_times][hour] << engagement_rate
        end

        # Average engagement by hour
        insights[:best_performing_times].each do |hour, rates|
          insights[:best_performing_times][hour] = rates.sum.to_f / rates.size
        end

        # Analyze content type performance
        posts.joins(:social_media_analytics).group(:content_type).each do |content_type, type_posts|
          total_engagement = type_posts.sum { |p| p.social_media_analytics.first&.engagement || 0 }
          total_reach = type_posts.sum { |p| p.social_media_analytics.first&.reach || 0 }

          insights[:content_type_performance][content_type] = {
            posts_count: type_posts.size,
            avg_engagement: total_engagement.to_f / type_posts.size,
            avg_reach: total_reach.to_f / type_posts.size,
            engagement_rate: total_reach > 0 ? (total_engagement.to_f / total_reach * 100).round(2) : 0
          }
        end

        insights
      end

      private

      def handle_response(response)
        if response.success?
          response.parsed_response
        else
          error_message = response.parsed_response&.dig('error', 'message') || 'Unknown API error'
          error_code = response.parsed_response&.dig('error', 'code') || response.code

          Rails.logger.error "Instagram Analytics API Error #{error_code}: #{error_message}"
          raise StandardError, "Instagram Analytics API Error (#{error_code}): #{error_message}"
        end
      rescue JSON::ParserError
        Rails.logger.error "Instagram Analytics API: Invalid JSON response - #{response.body}"
        raise StandardError, "Instagram Analytics API: Invalid response format"
      end

      def extract_post_analytics(insights_data)
        analytics = {
          impressions_count: 0,
          reach_count: 0,
          engagement_count: 0,
          likes_count: 0,
          comments_count: 0,
          shares_count: 0,
          saves_count: 0,
          profile_visits_count: 0,
          website_clicks_count: 0
        }

        insights_data.each do |insight|
          case insight['name']
          when 'impressions'
            analytics[:impressions_count] = insight['values']&.first&.dig('value').to_i
          when 'reach'
            analytics[:reach_count] = insight['values']&.first&.dig('value').to_i
          when 'engagement'
            analytics[:engagement_count] = insight['values']&.first&.dig('value').to_i
          when 'likes'
            analytics[:likes_count] = insight['values']&.first&.dig('value').to_i
          when 'comments'
            analytics[:comments_count] = insight['values']&.first&.dig('value').to_i
          when 'shares'
            analytics[:shares_count] = insight['values']&.first&.dig('value').to_i
          when 'saves'
            analytics[:saves_count] = insight['values']&.first&.dig('value').to_i
          when 'profile_visits'
            analytics[:profile_visits_count] = insight['values']&.first&.dig('value').to_i
          when 'website_clicks'
            analytics[:website_clicks_count] = insight['values']&.first&.dig('value').to_i
          end
        end

        analytics
      end

      def calculate_post_metrics(posts)
        return {} if posts.empty?

        total_impressions = posts.sum { |p| p.impressions_count || 0 }
        total_reach = posts.sum { |p| p.reach_count || 0 }
        total_engagement = posts.sum { |p| p.engagement_count || 0 }

        {
          total_posts: posts.count,
          total_impressions: total_impressions,
          total_reach: total_reach,
          total_engagement: total_engagement,
          avg_impressions_per_post: total_impressions.to_f / posts.count,
          avg_reach_per_post: total_reach.to_f / posts.count,
          avg_engagement_per_post: total_engagement.to_f / posts.count,
          overall_engagement_rate: total_reach > 0 ? (total_engagement.to_f / total_reach * 100).round(2) : 0
        }
      end

      def calculate_engagement_rate(analytics)
        return 0 unless analytics.reach && analytics.reach > 0
        ((analytics.engagement.to_f / analytics.reach) * 100).round(2)
      end

      def generate_summary_report(account_metrics, post_metrics, date_range)
        {
          period: {
            start_date: date_range.begin,
            end_date: date_range.end,
            days: (date_range.end - date_range.begin).to_i + 1
          },
          account_performance: account_metrics,
          content_performance: post_metrics,
          key_insights: generate_key_insights(account_metrics, post_metrics),
          recommendations: generate_recommendations(account_metrics, post_metrics)
        }
      end

      def generate_detailed_report(account_metrics, post_metrics, date_range)
        summary = generate_summary_report(account_metrics, post_metrics, date_range)

        summary.merge({
          posting_insights: get_posting_insights(date_range),
          top_performing_content: get_best_performing_content(5, 'engagement_rate'),
          audience_insights: get_audience_insights(date_range)
        })
      end

      def generate_key_insights(account_metrics, post_metrics)
        insights = []

        if post_metrics[:overall_engagement_rate] && post_metrics[:overall_engagement_rate] > 3
          insights << "Strong engagement rate of #{post_metrics[:overall_engagement_rate]}% (above industry average)"
        elsif post_metrics[:overall_engagement_rate] && post_metrics[:overall_engagement_rate] < 1
          insights << "Low engagement rate of #{post_metrics[:overall_engagement_rate]}% - consider improving content quality"
        end

        if post_metrics[:total_posts] && post_metrics[:total_posts] < 5
          insights << "Low posting frequency detected - consider posting more regularly"
        end

        if account_metrics[:total_reach] && account_metrics[:total_impressions]
          reach_rate = (account_metrics[:total_reach].to_f / account_metrics[:total_impressions] * 100).round(2)
          if reach_rate > 80
            insights << "Excellent reach rate of #{reach_rate}% indicates strong content distribution"
          end
        end

        insights
      end

      def generate_recommendations(account_metrics, post_metrics)
        recommendations = []

        if post_metrics[:overall_engagement_rate] && post_metrics[:overall_engagement_rate] < 2
          recommendations << {
            type: 'engagement',
            priority: 'high',
            message: 'Focus on creating more engaging content with clear calls-to-action'
          }
        end

        if post_metrics[:total_posts] && post_metrics[:total_posts] < 10
          recommendations << {
            type: 'frequency',
            priority: 'medium',
            message: 'Increase posting frequency to 1-2 times per day for better visibility'
          }
        end

        recommendations << {
          type: 'optimization',
          priority: 'low',
          message: 'Use Instagram Stories and Reels to diversify content and reach younger audiences'
        }

        recommendations
      end
    end
  end
end