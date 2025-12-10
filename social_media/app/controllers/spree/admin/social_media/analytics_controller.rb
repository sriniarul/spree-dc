module Spree
  module Admin
    module SocialMedia
      class AnalyticsController < Spree::Admin::BaseController
        before_action :authenticate_user!
        before_action :load_vendor
        before_action :authorize_social_media_access
        before_action :load_instagram_accounts
        before_action :set_current_account
        before_action :set_date_range

        def dashboard
          return redirect_to_account_setup if @instagram_accounts.empty?

          @analytics_summary = load_analytics_summary
          @chart_data = load_chart_data
          @content_type_performance = load_content_type_performance
          @top_posts = load_top_performing_posts
          @key_insights = generate_key_insights
          @recommendations = generate_recommendations
          @hashtag_performance = load_hashtag_performance
          @posting_times_data = load_posting_times_data
        end

        def chart_data
          metric = params[:metric] || 'engagement'
          data = load_chart_data_for_metric(metric)

          render json: {
            labels: data[:labels],
            values: data[:values]
          }
        end

        def top_posts
          sort_by = params[:sort] || 'engagement_rate'
          @top_posts = load_top_performing_posts(10, sort_by)

          render partial: 'top_posts_list', locals: { posts: @top_posts }
        end

        def export
          format = params[:format] || 'csv'
          analytics_service = Spree::SocialMedia::InstagramAnalyticsService.new(@current_account)

          case format
          when 'csv'
            export_csv(analytics_service)
          when 'excel'
            export_excel(analytics_service)
          when 'pdf'
            export_pdf(analytics_service)
          else
            redirect_back(fallback_location: dashboard_path, alert: 'Unsupported export format')
          end
        end

        def hashtag_analysis
          hashtags = analyze_hashtag_performance
          render json: { hashtags: hashtags }
        end

        def sync_account_analytics
          account = @vendor.social_media_accounts.find(params[:id])

          begin
            analytics_service = Spree::SocialMedia::InstagramAnalyticsService.new(account)

            # Sync account-level analytics
            account_insights = analytics_service.get_account_insights(@date_range)
            if account_insights['data'].present?
              sync_account_insights(account, account_insights['data'])
            end

            # Sync post-level analytics for recent posts
            recent_posts = account.social_media_posts.published.where(published_at: @date_range)
            sync_posts_analytics(recent_posts, analytics_service)

            account.update!(analytics_synced_at: Time.current)

            render json: {
              success: true,
              message: 'Analytics synced successfully',
              synced_at: account.analytics_synced_at
            }
          rescue => e
            Rails.logger.error "Analytics sync failed: #{e.message}"
            render json: {
              success: false,
              error: e.message
            }
          end
        end

        private

        def authenticate_user!
          unless spree_current_user
            flash[:error] = 'Please sign in to view analytics.'
            redirect_to spree.login_path
          end
        end

        def load_vendor
          vendor_id = params[:vendor_id] || session[:vendor_id]

          @vendor = if vendor_id.present?
                      Spree::Vendor.find(vendor_id)
                    elsif spree_current_user&.vendor
                      spree_current_user.vendor
                    else
                      Spree::Vendor.first
                    end

          unless @vendor
            flash[:error] = 'No vendor account found.'
            redirect_to spree.admin_path
          end
        end

        def authorize_social_media_access
          authorize! :read, :social_media_analytics
        end

        def load_instagram_accounts
          @instagram_accounts = @vendor.social_media_accounts
                                      .where(platform: 'instagram')
                                      .active
        end

        def set_current_account
          account_id = params[:account_id] || @instagram_accounts.first&.id
          @current_account = @instagram_accounts.find_by(id: account_id) || @instagram_accounts.first

          unless @current_account
            redirect_to_account_setup
          end
        end

        def set_date_range
          period_days = params[:period]&.to_i || 30
          @date_range = period_days.days.ago.to_date..Date.current
          @period_days = period_days
        end

        def redirect_to_account_setup
          flash[:info] = 'Connect your Instagram account to view analytics.'
          redirect_to spree.admin_social_media_accounts_path
        end

        def load_analytics_summary
          analytics_service = Spree::SocialMedia::InstagramAnalyticsService.new(@current_account)

          begin
            # Get current period insights
            current_insights = analytics_service.get_account_insights(@date_range)
            current_metrics = analytics_service.calculate_engagement_metrics(current_insights['data'] || [])

            # Get previous period for comparison
            previous_date_range = (@period_days * 2).days.ago.to_date..(@period_days.days.ago.to_date - 1.day)
            previous_insights = analytics_service.get_account_insights(previous_date_range)
            previous_metrics = analytics_service.calculate_engagement_metrics(previous_insights['data'] || [])

            # Calculate growth percentages
            summary = {
              total_followers: @current_account.followers_count || 0,
              total_reach: current_metrics[:total_reach] || 0,
              total_engagement: current_metrics[:total_engagement] || 0,
              engagement_rate: current_metrics[:engagement_rate] || 0,
              total_impressions: current_metrics[:total_impressions] || 0,
              profile_views: current_metrics[:total_profile_views] || 0
            }

            # Add growth calculations
            if previous_metrics[:total_reach] && previous_metrics[:total_reach] > 0
              summary[:reach_growth] = calculate_growth_percentage(
                current_metrics[:total_reach],
                previous_metrics[:total_reach]
              )
            end

            if previous_metrics[:total_engagement] && previous_metrics[:total_engagement] > 0
              summary[:engagement_growth] = calculate_growth_percentage(
                current_metrics[:total_engagement],
                previous_metrics[:total_engagement]
              )
            end

            summary
          rescue => e
            Rails.logger.warn "Failed to load analytics summary: #{e.message}"
            default_analytics_summary
          end
        end

        def load_chart_data
          load_chart_data_for_metric('engagement')
        end

        def load_chart_data_for_metric(metric)
          analytics_records = Spree::SocialMediaAnalytics
                                .where(social_media_account: @current_account)
                                .where(date: @date_range)
                                .order(:date)

          labels = []
          values = []

          @date_range.each do |date|
            labels << date.strftime('%b %d')
            record = analytics_records.find { |r| r.date == date }

            case metric
            when 'reach'
              values << (record&.reach || 0)
            when 'impressions'
              values << (record&.impressions || 0)
            when 'engagement'
              values << (record&.engagement || 0)
            else
              values << (record&.engagement || 0)
            end
          end

          { labels: labels, values: values }
        end

        def load_content_type_performance
          posts = @current_account.social_media_posts
                                 .published
                                 .joins(:social_media_analytics)
                                 .where(published_at: @date_range)

          performance = {}

          posts.group(:content_type).each do |content_type, type_posts|
            total_engagement = type_posts.sum { |p| p.social_media_analytics.first&.engagement || 0 }
            total_reach = type_posts.sum { |p| p.social_media_analytics.first&.reach || 0 }

            performance[content_type || 'feed'] = {
              posts_count: type_posts.size,
              avg_engagement: total_engagement.to_f / type_posts.size,
              avg_reach: total_reach.to_f / type_posts.size,
              engagement_rate: total_reach > 0 ? (total_engagement.to_f / total_reach * 100).round(2) : 0
            }
          end

          performance
        end

        def load_top_performing_posts(limit = 5, sort_by = 'engagement_rate')
          analytics_service = Spree::SocialMedia::InstagramAnalyticsService.new(@current_account)
          analytics_service.get_best_performing_content(limit, sort_by)
        end

        def generate_key_insights
          insights = []

          # Engagement rate insights
          if @analytics_summary[:engagement_rate] > 3
            insights << "Excellent engagement rate of #{@analytics_summary[:engagement_rate]}% - well above the industry average of 1-3%"
          elsif @analytics_summary[:engagement_rate] > 1
            insights << "Good engagement rate of #{@analytics_summary[:engagement_rate]}% - in line with industry standards"
          elsif @analytics_summary[:engagement_rate] > 0
            insights << "Engagement rate of #{@analytics_summary[:engagement_rate]}% has room for improvement"
          end

          # Growth insights
          if @analytics_summary[:reach_growth] && @analytics_summary[:reach_growth] > 10
            insights << "Strong reach growth of #{@analytics_summary[:reach_growth]}% indicates expanding audience"
          end

          # Content type insights
          best_content_type = @content_type_performance.max_by { |_, metrics| metrics[:engagement_rate] }
          if best_content_type && best_content_type[1][:engagement_rate] > 0
            insights << "#{best_content_type[0].humanize} posts perform best with #{best_content_type[1][:engagement_rate]}% engagement rate"
          end

          insights.first(3)
        end

        def generate_recommendations
          recommendations = []

          # Posting frequency recommendations
          posts_count = @current_account.social_media_posts.published.where(published_at: @date_range).count
          avg_posts_per_day = posts_count.to_f / @period_days

          if avg_posts_per_day < 0.5
            recommendations << {
              type: 'frequency',
              priority: 'high',
              message: 'Increase posting frequency to at least 3-4 posts per week for better engagement'
            }
          elsif avg_posts_per_day > 3
            recommendations << {
              type: 'frequency',
              priority: 'medium',
              message: 'Consider reducing posting frequency to avoid audience fatigue'
            }
          end

          # Engagement rate recommendations
          if @analytics_summary[:engagement_rate] < 1
            recommendations << {
              type: 'engagement',
              priority: 'high',
              message: 'Focus on creating more engaging content with clear calls-to-action and user interaction'
            }
          end

          # Content diversification
          if @content_type_performance.size == 1
            recommendations << {
              type: 'content_diversity',
              priority: 'medium',
              message: 'Experiment with different content types like Stories and Reels to reach wider audiences'
            }
          end

          recommendations.first(3)
        end

        def load_hashtag_performance
          # Analyze hashtags from recent posts
          recent_posts = @current_account.social_media_posts
                                       .published
                                       .where(published_at: @date_range)
                                       .joins(:social_media_analytics)

          hashtag_data = {}

          recent_posts.each do |post|
            hashtags = extract_hashtags(post.caption, post.hashtags)
            analytics = post.social_media_analytics.first

            hashtags.each do |hashtag|
              hashtag_data[hashtag] ||= { usage_count: 0, total_engagement: 0 }
              hashtag_data[hashtag][:usage_count] += 1
              hashtag_data[hashtag][:total_engagement] += (analytics&.engagement || 0)
            end
          end

          # Calculate average engagement and sort
          hashtag_performance = hashtag_data.map do |hashtag, data|
            {
              hashtag: hashtag.gsub('#', ''),
              usage_count: data[:usage_count],
              avg_engagement: data[:usage_count] > 0 ? (data[:total_engagement].to_f / data[:usage_count]).round(1) : 0
            }
          end

          hashtag_performance.sort_by { |h| -h[:avg_engagement] }.first(10)
        end

        def load_posting_times_data
          posts = @current_account.social_media_posts
                                 .published
                                 .joins(:social_media_analytics)
                                 .where(published_at: @date_range)

          hourly_data = Array.new(24, 0)

          posts.each do |post|
            hour = post.published_at.hour
            analytics = post.social_media_analytics.first
            engagement_rate = analytics && analytics.reach > 0 ?
                             (analytics.engagement.to_f / analytics.reach * 100) : 0
            hourly_data[hour] = engagement_rate if engagement_rate > hourly_data[hour]
          end

          hourly_data
        end

        def sync_account_insights(account, insights_data)
          @date_range.each do |date|
            # Find insights for this specific date
            date_insights = insights_data.select do |insight|
              insight['values'].any? { |v| v['end_time']&.to_date == date }
            end

            next if date_insights.empty?

            analytics_record = Spree::SocialMediaAnalytics.find_or_initialize_by(
              social_media_account: account,
              date: date
            )

            date_insights.each do |insight|
              value_data = insight['values'].find { |v| v['end_time']&.to_date == date }
              next unless value_data

              case insight['name']
              when 'impressions'
                analytics_record.impressions = value_data['value']
              when 'reach'
                analytics_record.reach = value_data['value']
              when 'profile_views'
                analytics_record.profile_visits = value_data['value']
              when 'website_clicks'
                analytics_record.website_clicks = value_data['value']
              end
            end

            analytics_record.raw_data = date_insights
            analytics_record.save!
          end
        end

        def sync_posts_analytics(posts, analytics_service)
          posts.each do |post|
            analytics_service.sync_post_analytics(post)
          rescue => e
            Rails.logger.warn "Failed to sync analytics for post #{post.id}: #{e.message}"
          end
        end

        def calculate_growth_percentage(current, previous)
          return 0 if previous.zero?
          ((current - previous).to_f / previous * 100).round(1)
        end

        def extract_hashtags(caption, hashtag_field = nil)
          hashtags = caption.scan(/#\w+/)

          if hashtag_field.present?
            field_hashtags = hashtag_field.split(/[\s,]+/).map { |tag| tag.start_with?('#') ? tag : "##{tag}" }
            hashtags.concat(field_hashtags)
          end

          hashtags.map(&:downcase).uniq
        end

        def default_analytics_summary
          {
            total_followers: @current_account.followers_count || 0,
            total_reach: 0,
            total_engagement: 0,
            engagement_rate: 0,
            total_impressions: 0,
            profile_views: 0
          }
        end

        def analyze_hashtag_performance
          load_hashtag_performance
        end

        def export_csv(analytics_service)
          report_data = analytics_service.generate_analytics_report(@date_range, :export)

          csv_data = generate_csv_data(report_data)

          send_data csv_data,
                    filename: "instagram_analytics_#{@current_account.username}_#{Date.current}.csv",
                    type: 'text/csv',
                    disposition: 'attachment'
        end

        def export_excel(analytics_service)
          # This would require the 'axlsx' gem or similar
          flash[:info] = 'Excel export feature coming soon!'
          redirect_back(fallback_location: dashboard_path)
        end

        def export_pdf(analytics_service)
          # This would require 'wicked_pdf' gem or similar
          flash[:info] = 'PDF export feature coming soon!'
          redirect_back(fallback_location: dashboard_path)
        end

        def generate_csv_data(report_data)
          require 'csv'

          CSV.generate do |csv|
            csv << ['Instagram Analytics Report']
            csv << ['Account', "@#{@current_account.username}"]
            csv << ['Period', "#{@date_range.begin} to #{@date_range.end}"]
            csv << []

            # Summary metrics
            csv << ['Summary Metrics']
            csv << ['Metric', 'Value']
            report_data[:account_performance].each do |key, value|
              csv << [key.to_s.humanize, value]
            end

            csv << []

            # Top posts
            if report_data[:top_performing_content]
              csv << ['Top Performing Posts']
              csv << ['Caption', 'Published At', 'Reach', 'Engagement', 'Engagement Rate']

              report_data[:top_performing_content].each do |post|
                csv << [
                  post[:caption],
                  post[:published_at],
                  post[:metrics][:reach],
                  post[:metrics][:engagement],
                  "#{post[:metrics][:engagement_rate]}%"
                ]
              end
            end
          end
        end

        def dashboard_path
          spree.dashboard_admin_social_media_analytics_path
        end
      end
    end
  end
end