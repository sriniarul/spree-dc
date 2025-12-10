module Spree
  module Admin
    module SocialMedia
      class ContentController < Spree::Admin::BaseController
        before_action :authenticate_user!
        before_action :load_vendor
        before_action :authorize_social_media_access
        before_action :find_social_media_account, only: [:show, :create_post]

        def index
          @social_media_accounts = @vendor.social_media_accounts.active
          @recent_posts = load_recent_posts
        end

        def show
          @platform = @account.platform
          @recent_posts = load_account_posts(@account)
          @analytics = load_account_analytics(@account)
        end

        def new_post
          @social_media_accounts = @vendor.social_media_accounts.active
          @post = Spree::SocialMediaPost.new
        end

        def validate_post
          @post = @vendor.social_media_posts.build(post_params)
          account_id = params[:social_media_account_id]
          @account = @vendor.social_media_accounts.find(account_id) if account_id.present?

          if @account&.platform == 'instagram'
            validator = Spree::SocialMedia::InstagramPostValidator.new(@post, @account)
            validation_result = validator.validation_summary

            render json: {
              valid: validation_result[:valid],
              errors: validation_result[:errors],
              warnings: validation_result[:warnings],
              recommendations: validation_result[:recommendations]
            }
          else
            render json: {
              valid: true,
              errors: [],
              warnings: [],
              recommendations: []
            }
          end
        end

        def schedule_dashboard
          @scheduled_posts = @vendor.social_media_posts
                                   .scheduled
                                   .includes(:social_media_account)
                                   .order(:scheduled_at)
                                   .limit(20)

          # Get scheduling suggestions for all connected platforms
          scheduler = Spree::SocialMedia::PostScheduler.new(@vendor)
          @scheduling_suggestions = []

          @vendor.social_media_accounts.active.each do |account|
            suggestions = scheduler.get_scheduling_suggestions(account.platform, 'feed', Time.zone.name)
            @scheduling_suggestions.concat(suggestions)
          end

          @scheduling_suggestions = @scheduling_suggestions.sort_by { |s| -s[:engagement_score] }.first(10)

          # Get week stats
          week_start = Time.current.beginning_of_week
          week_end = Time.current.end_of_week

          @week_stats = {
            scheduled: @vendor.social_media_posts.scheduled.count,
            published: @vendor.social_media_posts.published.where(published_at: week_start..week_end).count,
            optimal_percentage: calculate_optimal_percentage
          }

          # Check for schedule conflicts
          @schedule_conflicts = scheduler.get_schedule_conflicts(Time.current, 2.weeks.from_now)
        end

        def reschedule_post
          post = @vendor.social_media_posts.find(params[:id])
          new_time = params[:new_time]&.to_time

          scheduler = Spree::SocialMedia::PostScheduler.new(@vendor)

          if scheduler.reschedule_post(post.id, new_time)
            render json: { success: true, message: 'Post rescheduled successfully' }
          else
            render json: { success: false, error: scheduler.errors.join(', ') }
          end
        end

        def cancel_schedule
          post = @vendor.social_media_posts.find(params[:id])

          scheduler = Spree::SocialMedia::PostScheduler.new(@vendor)

          if scheduler.cancel_scheduled_post(post.id)
            render json: { success: true, message: 'Schedule cancelled successfully' }
          else
            render json: { success: false, error: scheduler.errors.join(', ') }
          end
        end

        def bulk_schedule
          posts_data = params[:posts] || []
          strategy = params[:strategy] || 'optimal'

          scheduler = Spree::SocialMedia::PostScheduler.new(@vendor)
          results = scheduler.bulk_schedule(posts_data, strategy)

          successful_count = results.count { |r| r[:success] }
          failed_count = results.count { |r| !r[:success] }

          if failed_count == 0
            render json: {
              success: true,
              message: "Successfully scheduled #{successful_count} posts",
              results: results
            }
          else
            render json: {
              success: false,
              message: "Scheduled #{successful_count} posts, #{failed_count} failed",
              results: results
            }
          end
        end

        def get_optimal_times
          platform = params[:platform] || 'instagram'
          content_type = params[:content_type] || 'feed'
          timezone = params[:timezone] || Time.zone.name

          scheduler = Spree::SocialMedia::PostScheduler.new(@vendor)
          suggestions = scheduler.get_scheduling_suggestions(platform, content_type, timezone)

          render json: { suggestions: suggestions }
        end

        def create_post
          @post = @vendor.social_media_posts.build(post_params)
          @post.social_media_account = @account

          # Handle media file uploads
          if params[:media_files].present?
            params[:media_files].each do |file|
              @post.media_attachments.attach(file)
            end
          end

          # Validate Instagram post requirements
          if @account.platform == 'instagram'
            validator = Spree::SocialMedia::InstagramPostValidator.new(@post, @account)
            validation_result = validator.validation_summary

            unless validation_result[:valid]
              @social_media_accounts = @vendor.social_media_accounts.active
              flash.now[:error] = "Instagram validation failed: #{validation_result[:errors].join(', ')}"

              if validation_result[:warnings].any?
                flash.now[:warning] = "Warnings: #{validation_result[:warnings].join(', ')}"
              end

              @validation_result = validation_result
              render :new_post
              return
            end

            # Show warnings even if validation passes
            if validation_result[:warnings].any?
              flash[:warning] = "Post created with warnings: #{validation_result[:warnings].join(', ')}"
            end

            # Show recommendations
            if validation_result[:recommendations].any?
              flash[:info] = "Recommendations: #{validation_result[:recommendations].first(2).join(', ')}"
            end
          end

          if @post.save
            # Schedule or publish immediately
            if params[:publish_now] == 'true'
              Spree::SocialMedia::PublishPostJob.perform_later(@post.id)
              flash[:success] = 'Post is being published to Instagram!'
            else
              flash[:success] = 'Post has been scheduled successfully!'
            end

            redirect_to spree.admin_social_media_content_path(@account)
          else
            @social_media_accounts = @vendor.social_media_accounts.active
            flash.now[:error] = "Failed to create post: #{@post.errors.full_messages.join(', ')}"
            render :new_post
          end
        end

        def publish_post
          @post = @vendor.social_media_posts.find(params[:id])

          if @post.may_publish?
            Spree::SocialMedia::PublishPostJob.perform_later(@post.id)
            flash[:success] = 'Post is being published!'
          else
            flash[:error] = "Cannot publish post in #{@post.status} status"
          end

          redirect_to spree.admin_social_media_content_path(@post.social_media_account)
        end

        def delete_post
          @post = @vendor.social_media_posts.find(params[:id])

          if @post.destroy
            flash[:success] = 'Post has been deleted'
          else
            flash[:error] = 'Failed to delete post'
          end

          redirect_back(fallback_location: spree.admin_social_media_path)
        end

        private

        def authenticate_user!
          unless spree_current_user
            flash[:error] = 'Please sign in to manage social media content.'
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
                      Spree::Vendor.first # Fallback for single vendor setups
                    end

          unless @vendor
            flash[:error] = 'No vendor account found. Please contact support.'
            redirect_to spree.admin_path
          end
        end

        def authorize_social_media_access
          authorize! :manage, :social_media_content
        end

        def find_social_media_account
          @account = @vendor.social_media_accounts.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          flash[:error] = 'Social media account not found'
          redirect_to spree.admin_social_media_path
        end

        def post_params
          params.require(:spree_social_media_post).permit(
            :content,
            :caption,
            :content_type,
            :scheduled_at,
            :hashtags,
            :product_mentions,
            media_urls: [],
            product_tags: []
          )
        end

        def load_recent_posts
          return [] unless @vendor.social_media_accounts.any?

          @vendor.social_media_posts
                 .includes(:social_media_account)
                 .recent
                 .limit(20)
        end

        def load_account_posts(account)
          account.social_media_posts
                 .includes(:social_media_account)
                 .recent
                 .limit(20)
        end

        def load_account_analytics(account)
          return {} unless account.active?

          case account.platform
          when 'instagram'
            load_instagram_analytics(account)
          when 'facebook'
            load_facebook_analytics(account)
          when 'youtube'
            load_youtube_analytics(account)
          else
            {}
          end
        end

        def load_instagram_analytics(account)
          begin
            service = Spree::SocialMedia::InstagramApiService.new(account)
            account_info = service.get_account_info rescue {}

            {
              followers_count: account_info['followers_count'] || account.followers_count || 0,
              posts_count: account_info['media_count'] || account.posts_count || 0,
              engagement_rate: calculate_engagement_rate(account),
              recent_insights: get_recent_insights(account)
            }
          rescue => e
            Rails.logger.error "Failed to load Instagram analytics: #{e.message}"
            {
              followers_count: account.followers_count || 0,
              posts_count: account.posts_count || 0,
              engagement_rate: 0,
              recent_insights: {}
            }
          end
        end

        def load_facebook_analytics(account)
          begin
            service = Spree::SocialMedia::FacebookApiService.new(account)
            page_info = service.get_page_info rescue {}

            {
              followers_count: page_info['followers_count'] || account.followers_count || 0,
              posts_count: account.posts_count || 0,
              engagement_rate: calculate_engagement_rate(account),
              recent_insights: get_recent_insights(account)
            }
          rescue => e
            Rails.logger.error "Failed to load Facebook analytics: #{e.message}"
            {
              followers_count: account.followers_count || 0,
              posts_count: account.posts_count || 0,
              engagement_rate: 0,
              recent_insights: {}
            }
          end
        end

        def load_youtube_analytics(account)
          {
            followers_count: account.followers_count || 0,
            posts_count: account.posts_count || 0,
            engagement_rate: calculate_engagement_rate(account),
            recent_insights: get_recent_insights(account)
          }
        end

        def calculate_engagement_rate(account)
          # Calculate based on recent posts performance
          recent_posts = account.social_media_posts.published.recent.limit(10)
          return 0 if recent_posts.empty? || account.followers_count.to_i.zero?

          total_engagement = recent_posts.sum(&:engagement_count)
          average_engagement = total_engagement.to_f / recent_posts.count
          (average_engagement / account.followers_count * 100).round(2)
        end

        def get_recent_insights(account)
          # Get analytics from the last 30 days
          start_date = 30.days.ago
          end_date = Date.current

          Spree::SocialMediaAnalytics
            .where(social_media_account: account)
            .where(date: start_date..end_date)
            .order(:date)
            .limit(30)
            .pluck(:date, :impressions, :reach, :engagement)
            .map { |date, impressions, reach, engagement|
              {
                date: date,
                impressions: impressions || 0,
                reach: reach || 0,
                engagement: engagement || 0
              }
            }
        end

        def calculate_optimal_percentage
          recent_posts = @vendor.social_media_posts.published.where(published_at: 30.days.ago..Time.current)
          return 0 if recent_posts.empty?

          optimal_count = recent_posts.count do |post|
            published_time = post.published_at
            platform = post.social_media_account.platform

            optimal_times = Spree::SocialMedia::PostScheduler::OPTIMAL_TIMES[platform.to_sym]
            next false unless optimal_times

            hour = published_time.hour
            is_weekend = published_time.saturday? || published_time.sunday?

            relevant_times = is_weekend ? optimal_times[:weekends] : optimal_times[:weekdays]
            relevant_times.include?(hour)
          end

          ((optimal_count.to_f / recent_posts.count) * 100).round(1)
        end
      end
    end
  end
end