module Spree
  module Admin
    module SocialMedia
      class HashtagsController < Spree::Admin::BaseController
        before_action :authenticate_user!
        before_action :load_vendor
        before_action :authorize_social_media_access
        before_action :load_instagram_accounts
        before_action :set_current_account
        before_action :load_hashtag_service

        def index
          @hashtag_analysis = @hashtag_service.analyze_account_hashtag_performance(30)
          @trending_hashtags = load_trending_hashtags_cache
        end

        def search
          query = params[:query]
          limit = params[:limit]&.to_i || 25

          if query.present?
            result = @hashtag_service.search_hashtags(query, limit)

            render json: {
              success: result[:error].nil?,
              hashtags: result[:hashtags] || [],
              error: result[:error]
            }
          else
            render json: {
              success: false,
              hashtags: [],
              error: 'Search query is required'
            }
          end
        end

        def insights
          hashtag_id = params[:hashtag_id]

          if hashtag_id.present?
            insights = @hashtag_service.get_hashtag_insights(hashtag_id)

            render json: {
              success: insights[:success] || false,
              insights: insights[:hashtag_info],
              recent_media: insights[:recent_media] || [],
              performance_metrics: insights[:performance_metrics] || {},
              error: insights[:error]
            }
          else
            render json: {
              success: false,
              error: 'Hashtag ID is required'
            }
          end
        end

        def suggestions
          content_description = params[:content_description] || ''
          caption = params[:caption] || ''
          existing_hashtags = params[:existing_hashtags] || []

          suggestions = @hashtag_service.suggest_hashtags_for_content(
            content_description,
            caption,
            existing_hashtags
          )

          render json: {
            success: true,
            suggestions: suggestions[:suggestions],
            ranked_suggestions: suggestions[:ranked_suggestions],
            recommendation: suggestions[:recommendation]
          }
        end

        def strategy
          business_category = params[:business_category] || @vendor.business_category || 'general'
          target_audience = parse_target_audience(params[:target_audience])
          content_goals = parse_content_goals(params[:content_goals])

          strategy = @hashtag_service.generate_hashtag_strategy(
            business_category,
            target_audience,
            content_goals
          )

          if request.xhr?
            render json: {
              success: true,
              strategy: strategy[:strategy],
              implementation_plan: strategy[:implementation_plan],
              monitoring_recommendations: strategy[:monitoring_recommendations]
            }
          else
            @hashtag_strategy = strategy
          end
        end

        def performance_report
          days_back = params[:days]&.to_i || 30

          @performance_data = @hashtag_service.analyze_account_hashtag_performance(days_back)
          @report_period = days_back

          respond_to do |format|
            format.html { render :performance_report }
            format.json { render json: @performance_data }
            format.csv { export_performance_csv(@performance_data) }
          end
        end

        def trending_analysis
          # Get trending hashtags for the account's niche
          business_category = @vendor.business_category || 'general'

          begin
            # This would typically connect to external APIs for trending data
            @trending_data = {
              general_trending: get_general_trending_hashtags,
              niche_trending: get_niche_trending_hashtags(business_category),
              competitor_hashtags: analyze_competitor_hashtags,
              recommended_action: generate_trending_recommendations
            }

            render json: @trending_data
          rescue => e
            render json: {
              success: false,
              error: "Failed to analyze trending hashtags: #{e.message}"
            }
          end
        end

        def validate_hashtags
          hashtags = params[:hashtags] || []

          validation_results = hashtags.map do |hashtag|
            {
              hashtag: hashtag,
              valid: validate_single_hashtag(hashtag),
              issues: identify_hashtag_issues(hashtag),
              recommendations: get_hashtag_recommendations(hashtag)
            }
          end

          render json: {
            success: true,
            validation_results: validation_results,
            summary: generate_validation_summary(validation_results)
          }
        end

        def save_hashtag_set
          name = params[:name]
          hashtags = params[:hashtags] || []
          description = params[:description] || ''

          if name.present? && hashtags.any?
            hashtag_set = @vendor.hashtag_sets.build(
              name: name,
              hashtags: hashtags.join(' '),
              description: description,
              social_media_account: @current_account
            )

            if hashtag_set.save
              render json: {
                success: true,
                message: 'Hashtag set saved successfully',
                hashtag_set_id: hashtag_set.id
              }
            else
              render json: {
                success: false,
                error: hashtag_set.errors.full_messages.join(', ')
              }
            end
          else
            render json: {
              success: false,
              error: 'Name and hashtags are required'
            }
          end
        end

        def load_hashtag_sets
          hashtag_sets = @vendor.hashtag_sets
                               .where(social_media_account: [@current_account, nil])
                               .order(:name)

          render json: {
            success: true,
            hashtag_sets: hashtag_sets.map do |set|
              {
                id: set.id,
                name: set.name,
                hashtags: set.hashtags.split(' '),
                description: set.description,
                usage_count: set.usage_count || 0,
                last_used: set.last_used_at
              }
            end
          }
        end

        def auto_suggest
          post_content = params[:post_content] || ''
          media_type = params[:media_type] || 'image'
          target_audience = params[:target_audience] || 'general'

          begin
            # Analyze post content for automatic suggestions
            suggestions = @hashtag_service.suggest_hashtags_for_content(post_content)

            # Add AI-powered suggestions based on image analysis (if available)
            if media_type == 'image' && params[:image_url].present?
              image_suggestions = analyze_image_for_hashtags(params[:image_url])
              suggestions[:suggestions][:ai_generated] = image_suggestions
            end

            render json: {
              success: true,
              auto_suggestions: suggestions[:ranked_suggestions].first(10),
              confidence_score: suggestions[:recommendation][:confidence_score],
              explanation: generate_suggestion_explanation(suggestions)
            }
          rescue => e
            render json: {
              success: false,
              error: "Auto-suggestion failed: #{e.message}"
            }
          end
        end

        private

        def authenticate_user!
          unless spree_current_user
            flash[:error] = 'Please sign in to manage hashtags.'
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
          authorize! :manage, :social_media_hashtags
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
            if request.xhr?
              render json: { success: false, error: 'Instagram account not found' }
            else
              flash[:info] = 'Connect your Instagram account to manage hashtags.'
              redirect_to spree.admin_social_media_accounts_path
            end
          end
        end

        def load_hashtag_service
          @hashtag_service = Spree::SocialMedia::HashtagService.new(@current_account)
        end

        def load_trending_hashtags_cache
          # Cache trending hashtags for 1 hour to avoid excessive API calls
          Rails.cache.fetch("trending_hashtags_#{@current_account.id}", expires_in: 1.hour) do
            get_general_trending_hashtags
          end
        end

        def parse_target_audience(audience_param)
          return ['general'] if audience_param.blank?

          if audience_param.is_a?(String)
            audience_param.split(',').map(&:strip)
          else
            Array(audience_param)
          end
        end

        def parse_content_goals(goals_param)
          return ['engagement'] if goals_param.blank?

          if goals_param.is_a?(String)
            goals_param.split(',').map(&:strip)
          else
            Array(goals_param)
          end
        end

        def export_performance_csv(performance_data)
          require 'csv'

          csv_data = CSV.generate do |csv|
            csv << ['Hashtag Performance Report']
            csv << ['Account', "@#{@current_account.username}"]
            csv << ['Period', "#{@report_period} days"]
            csv << []

            csv << ['Hashtag', 'Usage Count', 'Avg Reach', 'Avg Engagement', 'Engagement Rate', 'Performance Score', 'Consistency']

            performance_data[:performance_data].each do |hashtag|
              csv << [
                hashtag[:name],
                hashtag[:usage_count],
                hashtag[:avg_reach],
                hashtag[:avg_engagement],
                "#{hashtag[:avg_engagement_rate]}%",
                hashtag[:performance_score],
                "#{hashtag[:consistency]}%"
              ]
            end

            csv << []
            csv << ['Summary']
            performance_data[:summary].each do |key, value|
              csv << [key.to_s.humanize, value]
            end
          end

          send_data csv_data,
                    filename: "hashtag_performance_#{@current_account.username}_#{Date.current}.csv",
                    type: 'text/csv',
                    disposition: 'attachment'
        end

        def get_general_trending_hashtags
          # This would connect to trending hashtag APIs
          # For demo purposes, return static trending hashtags
          [
            { name: '#trending', difficulty: 'high', estimated_reach: 1000000 },
            { name: '#viral', difficulty: 'high', estimated_reach: 800000 },
            { name: '#explore', difficulty: 'high', estimated_reach: 1200000 },
            { name: '#instagood', difficulty: 'high', estimated_reach: 900000 },
            { name: '#photooftheday', difficulty: 'high', estimated_reach: 700000 }
          ]
        end

        def get_niche_trending_hashtags(business_category)
          # Return trending hashtags specific to business category
          case business_category.downcase
          when 'fashion', 'clothing'
            ['#ootd', '#fashion', '#style', '#outfit', '#fashionista']
          when 'food', 'restaurant', 'catering'
            ['#foodie', '#instafood', '#foodporn', '#delicious', '#yummy']
          when 'fitness', 'health', 'wellness'
            ['#fitness', '#workout', '#health', '#wellness', '#fitnessmotivation']
          when 'beauty', 'cosmetics'
            ['#beauty', '#makeup', '#skincare', '#beautytips', '#cosmetics']
          else
            ['#business', '#entrepreneur', '#startup', '#success', '#motivation']
          end
        end

        def analyze_competitor_hashtags
          # This would analyze competitors' hashtag usage
          # For demo purposes, return sample data
          {
            top_competitor_hashtags: ['#competitor1', '#industry', '#market'],
            hashtag_gaps: ['#opportunity', '#niche', '#untapped'],
            overlap_analysis: {
              shared_hashtags: 15,
              unique_hashtags: 25,
              opportunity_score: 78
            }
          }
        end

        def generate_trending_recommendations
          [
            'Consider incorporating 2-3 trending hashtags in your next posts',
            'Focus on niche hashtags that align with your brand values',
            'Monitor competitor hashtag performance weekly',
            'Test new trending hashtags with A/B testing approach'
          ]
        end

        def validate_single_hashtag(hashtag)
          # Basic hashtag validation
          hashtag = hashtag.strip
          return false if hashtag.blank?
          return false unless hashtag.start_with?('#')
          return false if hashtag.length > 100
          return false if hashtag.match?(/[^#\w]/) # Only allow word characters and #

          true
        end

        def identify_hashtag_issues(hashtag)
          issues = []

          issues << 'Missing # symbol' unless hashtag.start_with?('#')
          issues << 'Too long (max 100 characters)' if hashtag.length > 100
          issues << 'Contains invalid characters' if hashtag.match?(/[^#\w]/)
          issues << 'Too generic - may have low engagement' if generic_hashtag?(hashtag)
          issues << 'Potentially banned or flagged' if potentially_banned?(hashtag)

          issues
        end

        def get_hashtag_recommendations(hashtag)
          recommendations = []

          if generic_hashtag?(hashtag)
            recommendations << 'Consider more specific, niche hashtags'
          end

          if hashtag.length < 5
            recommendations << 'Try longer, more descriptive hashtags'
          end

          recommendations << 'Research this hashtag performance before using'
          recommendations
        end

        def generate_validation_summary(validation_results)
          valid_count = validation_results.count { |result| result[:valid] }
          total_count = validation_results.length

          {
            total_hashtags: total_count,
            valid_hashtags: valid_count,
            invalid_hashtags: total_count - valid_count,
            overall_score: total_count > 0 ? (valid_count.to_f / total_count * 100).round : 0,
            recommendations: generate_overall_recommendations(validation_results)
          }
        end

        def generate_overall_recommendations(validation_results)
          recommendations = []

          invalid_count = validation_results.count { |result| !result[:valid] }
          if invalid_count > 0
            recommendations << "Fix #{invalid_count} invalid hashtags"
          end

          generic_count = validation_results.count do |result|
            result[:issues].any? { |issue| issue.include?('generic') }
          end
          if generic_count > 2
            recommendations << 'Consider more niche-specific hashtags'
          end

          recommendations << 'Research hashtag performance before publishing' if validation_results.length > 10
          recommendations
        end

        def generic_hashtag?(hashtag)
          generic_hashtags = %w[#love #instagood #photooftheday #beautiful #happy #follow #like4like #followme]
          generic_hashtags.include?(hashtag.downcase)
        end

        def potentially_banned?(hashtag)
          # List of potentially banned or problematic hashtags
          banned_patterns = %w[#follow4follow #like4like #spam #bot]
          banned_patterns.any? { |pattern| hashtag.downcase.include?(pattern) }
        end

        def analyze_image_for_hashtags(image_url)
          # This would integrate with image recognition APIs
          # For demo purposes, return sample suggestions
          [
            { name: '#photography', confidence: 85 },
            { name: '#product', confidence: 78 },
            { name: '#brand', confidence: 72 }
          ]
        end

        def generate_suggestion_explanation(suggestions)
          top_suggestion = suggestions[:ranked_suggestions].first
          return 'No suggestions available' unless top_suggestion

          case top_suggestion[:category]
          when :trending
            'Based on current trending hashtags in your niche'
          when :niche_specific
            'Specific to your content and industry'
          when :brand_specific
            'Related to your brand and business'
          else
            'Generated based on content analysis and engagement potential'
          end
        end
      end
    end
  end
end