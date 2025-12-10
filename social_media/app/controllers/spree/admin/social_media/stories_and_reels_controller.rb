module Spree
  module Admin
    module SocialMedia
      class StoriesAndReelsController < Spree::Admin::BaseController
        before_action :authenticate_user!
        before_action :load_vendor
        before_action :authorize_social_media_access
        before_action :load_instagram_accounts
        before_action :set_current_account

        def index
          @stories = load_stories
          @reels = load_reels
          @analytics_summary = load_stories_reels_analytics
        end

        def new_story
          @story_form = build_story_form
          @templates = load_story_templates
          @trending_stickers = get_trending_story_features
        end

        def create_story
          @story_form = build_story_form(story_params)

          if @story_form.valid?
            result = publish_or_schedule_story(@story_form.to_h)

            if result[:success]
              if params[:schedule_for].present?
                flash[:success] = "Story scheduled successfully for #{params[:schedule_for]}"
              else
                flash[:success] = 'Story published successfully!'
              end
              redirect_to admin_social_media_stories_and_reels_path
            else
              flash.now[:error] = "Failed to publish story: #{result[:errors].join(', ')}"
              @templates = load_story_templates
              @trending_stickers = get_trending_story_features
              render :new_story, status: :unprocessable_entity
            end
          else
            flash.now[:error] = 'Please correct the errors below.'
            @templates = load_story_templates
            @trending_stickers = get_trending_story_features
            render :new_story, status: :unprocessable_entity
          end
        end

        def new_reel
          @reel_form = build_reel_form
          @templates = load_reel_templates
          @trending_audio = get_trending_audio
          @performance_tips = get_reel_performance_tips
        end

        def create_reel
          @reel_form = build_reel_form(reel_params)

          if @reel_form.valid?
            result = publish_or_schedule_reel(@reel_form.to_h)

            if result[:success]
              if params[:schedule_for].present?
                flash[:success] = "Reel scheduled successfully for #{params[:schedule_for]}"
              else
                flash[:success] = 'Reel published successfully!'
              end
              redirect_to admin_social_media_stories_and_reels_path
            else
              flash.now[:error] = "Failed to publish reel: #{result[:errors].join(', ')}"
              @templates = load_reel_templates
              @trending_audio = get_trending_audio
              @performance_tips = get_reel_performance_tips
              render :new_reel, status: :unprocessable_entity
            end
          else
            flash.now[:error] = 'Please correct the errors below.'
            @templates = load_reel_templates
            @trending_audio = get_trending_audio
            @performance_tips = get_reel_performance_tips
            render :new_reel, status: :unprocessable_entity
          end
        end

        def validate_story_media
          if params[:media].present?
            story_service = Spree::SocialMedia::InstagramStoryService.new(@current_account)
            validation = story_service.validate_story_requirements(params[:media])

            render json: {
              valid: validation[:valid],
              errors: validation[:errors],
              warnings: validation[:warnings],
              suggestions: generate_story_suggestions(validation)
            }
          else
            render json: {
              valid: false,
              errors: ['No media file provided'],
              warnings: [],
              suggestions: []
            }
          end
        end

        def validate_reel_video
          if params[:video].present?
            reel_service = Spree::SocialMedia::InstagramReelService.new(@current_account)
            validation = reel_service.validate_reel_requirements(params[:video])

            render json: {
              valid: validation[:valid],
              errors: validation[:errors],
              warnings: validation[:warnings],
              suggestions: generate_reel_suggestions(validation),
              optimization_tips: get_video_optimization_tips(params[:video])
            }
          else
            render json: {
              valid: false,
              errors: ['No video file provided'],
              warnings: [],
              suggestions: []
            }
          end
        end

        def preview_story
          story_data = build_story_preview_data(params)

          render json: {
            success: true,
            preview: {
              media_preview: generate_media_preview(story_data[:media]),
              text_overlay: story_data[:text_overlay],
              stickers: story_data[:stickers] || [],
              duration: calculate_story_duration(story_data),
              interactive_elements: count_interactive_elements(story_data[:stickers])
            }
          }
        end

        def preview_reel
          reel_data = build_reel_preview_data(params)
          reel_service = Spree::SocialMedia::InstagramReelService.new(@current_account)

          # Generate hashtag suggestions
          hashtag_suggestions = reel_service.generate_reel_hashtags(reel_data[:caption] || '')

          # Optimize caption if requested
          caption_optimization = reel_service.optimize_reel_caption(reel_data[:caption] || '')

          render json: {
            success: true,
            preview: {
              video_preview: generate_video_preview(reel_data[:video]),
              caption: reel_data[:caption],
              optimized_caption: caption_optimization[:optimized],
              hashtag_suggestions: hashtag_suggestions,
              estimated_reach: calculate_estimated_reach(reel_data),
              performance_score: calculate_performance_score(reel_data)
            }
          }
        end

        def trending_audio
          reel_service = Spree::SocialMedia::InstagramReelService.new(@current_account)
          result = reel_service.get_trending_audio

          render json: result
        end

        def search_audio
          query = params[:query]
          reel_service = Spree::SocialMedia::InstagramReelService.new(@current_account)
          result = reel_service.search_audio(query)

          render json: result
        end

        def analytics
          @analytics_data = {
            stories: load_story_analytics,
            reels: load_reel_analytics,
            comparison: load_stories_vs_reels_comparison,
            top_performing: load_top_performing_content
          }

          respond_to do |format|
            format.html { render :analytics }
            format.json { render json: @analytics_data }
          end
        end

        def export_analytics
          analytics_service = Spree::SocialMedia::InstagramAnalyticsService.new(@current_account)

          case params[:format]
          when 'csv'
            export_stories_reels_csv
          when 'json'
            export_stories_reels_json
          else
            flash[:error] = 'Unsupported export format'
            redirect_to analytics_admin_social_media_stories_and_reels_path
          end
        end

        def bulk_actions
          content_ids = params[:content_ids] || []
          action = params[:bulk_action]

          case action
          when 'delete'
            perform_bulk_delete(content_ids)
          when 'archive'
            perform_bulk_archive(content_ids)
          else
            flash[:error] = 'Invalid bulk action'
          end

          redirect_to admin_social_media_stories_and_reels_path
        end

        private

        def authenticate_user!
          unless spree_current_user
            flash[:error] = 'Please sign in to manage stories and reels.'
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
          authorize! :manage, :social_media_content
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
            flash[:info] = 'Connect your Instagram account to create stories and reels.'
            redirect_to spree.admin_social_media_accounts_path
          end
        end

        def load_stories
          @current_account.social_media_posts
                         .where(content_type: 'story')
                         .order(created_at: :desc)
                         .limit(20)
        end

        def load_reels
          @current_account.social_media_posts
                         .where(content_type: 'reel')
                         .order(created_at: :desc)
                         .limit(20)
        end

        def load_stories_reels_analytics
          stories_count = @current_account.social_media_posts.where(content_type: 'story').count
          reels_count = @current_account.social_media_posts.where(content_type: 'reel').count

          {
            stories_count: stories_count,
            reels_count: reels_count,
            total_content: stories_count + reels_count,
            this_week: {
              stories: @current_account.social_media_posts
                                      .where(content_type: 'story')
                                      .where('created_at > ?', 1.week.ago)
                                      .count,
              reels: @current_account.social_media_posts
                                    .where(content_type: 'reel')
                                    .where('created_at > ?', 1.week.ago)
                                    .count
            }
          }
        end

        def build_story_form(params = {})
          StoryForm.new(params)
        end

        def build_reel_form(params = {})
          ReelForm.new(params)
        end

        def story_params
          params.require(:story).permit(
            :media, :text_overlay, :background_color, :font_style,
            stickers: [], sticker_positions: {}
          )
        end

        def reel_params
          params.require(:reel).permit(
            :video, :caption, :audio_name, :cover_image, :cover_offset,
            :location_id, :optimize_caption
          )
        end

        def load_story_templates
          @vendor.social_media_templates
                .where(template_type: 'story')
                .active
                .order(:name)
        end

        def load_reel_templates
          @vendor.social_media_templates
                .where(template_type: 'reel')
                .active
                .order(:name)
        end

        def get_trending_story_features
          [
            { type: 'poll', name: 'Poll Sticker', popular: true },
            { type: 'question', name: 'Question Sticker', popular: true },
            { type: 'countdown', name: 'Countdown Sticker', popular: false },
            { type: 'quiz', name: 'Quiz Sticker', popular: false }
          ]
        end

        def get_trending_audio
          # This would connect to Instagram's trending audio API
          [
            { id: '1', name: 'Trending Audio 1', duration: '30s', usage_count: 5000 },
            { id: '2', name: 'Trending Audio 2', duration: '15s', usage_count: 3500 },
            { id: '3', name: 'Trending Audio 3', duration: '45s', usage_count: 2800 }
          ]
        end

        def get_reel_performance_tips
          reel_service = Spree::SocialMedia::InstagramReelService.new(@current_account)
          reel_service.get_reel_performance_tips
        end

        def publish_or_schedule_story(story_data)
          story_service = Spree::SocialMedia::InstagramStoryService.new(@current_account)

          if params[:schedule_for].present?
            publish_time = DateTime.parse(params[:schedule_for])
            story_service.schedule_story(story_data, publish_time)
          else
            story_service.publish_story(story_data)
          end
        end

        def publish_or_schedule_reel(reel_data)
          reel_service = Spree::SocialMedia::InstagramReelService.new(@current_account)

          if params[:schedule_for].present?
            publish_time = DateTime.parse(params[:schedule_for])
            reel_service.schedule_reel(reel_data, publish_time)
          else
            reel_service.publish_reel(reel_data)
          end
        end

        def generate_story_suggestions(validation)
          suggestions = []

          if validation[:warnings].include?('aspect ratio')
            suggestions << 'Consider cropping your image to 9:16 aspect ratio for better fit'
          end

          if validation[:errors].any? { |e| e.include?('file size') }
            suggestions << 'Compress your media file to reduce size'
          end

          suggestions << 'Add interactive elements like polls or questions to boost engagement'
          suggestions
        end

        def generate_reel_suggestions(validation)
          suggestions = []

          if validation[:warnings].include?('vertical')
            suggestions << 'Vertical videos (9:16) get better reach on Instagram'
          end

          if validation[:warnings].include?('resolution')
            suggestions << 'Higher resolution videos get better visibility'
          end

          suggestions << 'Use trending audio to increase discoverability'
          suggestions << 'Hook viewers in the first 3 seconds'
          suggestions
        end

        def get_video_optimization_tips(video)
          tips = []

          # Analyze video file
          if video.respond_to?(:blob)
            size = video.blob.byte_size
            metadata = video.blob.metadata || {}

            if size > 100.megabytes
              tips << 'Consider compressing the video to reduce file size'
            end

            if metadata['width'] && metadata['height']
              aspect_ratio = metadata['width'].to_f / metadata['height']
              if aspect_ratio > 0.7
                tips << 'Vertical videos perform better on Instagram Reels'
              end
            end
          end

          tips << 'Add captions for better accessibility'
          tips << 'Use trending hashtags to increase reach'
          tips
        end

        # Form classes for validation
        class StoryForm
          include ActiveModel::Model
          include ActiveModel::Attributes

          attribute :media
          attribute :text_overlay, :string
          attribute :background_color, :string, default: '#000000'
          attribute :font_style, :string, default: 'normal'
          attribute :stickers, array: true, default: []

          validates :media, presence: true

          def to_h
            {
              media: media,
              text_overlay: text_overlay,
              background_color: background_color,
              font_style: font_style,
              stickers: stickers,
              media_type: determine_media_type
            }
          end

          private

          def determine_media_type
            return 'IMAGE' unless media

            content_type = media.content_type || ''
            content_type.start_with?('image/') ? 'IMAGE' : 'VIDEO'
          end
        end

        class ReelForm
          include ActiveModel::Model
          include ActiveModel::Attributes

          attribute :video
          attribute :caption, :string
          attribute :audio_name, :string
          attribute :cover_image
          attribute :cover_offset, :integer, default: 0
          attribute :location_id, :string
          attribute :optimize_caption, :boolean, default: false

          validates :video, presence: true
          validates :caption, length: { maximum: 2200 }

          def to_h
            {
              video: video,
              caption: caption,
              audio_name: audio_name,
              cover_image: cover_image,
              cover_offset: cover_offset,
              location_id: location_id,
              optimization_applied: optimize_caption
            }
          end
        end

        # Additional helper methods would continue here...
        # (Truncated for brevity, but would include all the analytics loading,
        # export methods, and other supporting functionality)

        def build_story_preview_data(params)
          {
            media: params[:media],
            text_overlay: params[:text_overlay],
            stickers: parse_stickers(params[:stickers])
          }
        end

        def build_reel_preview_data(params)
          {
            video: params[:video],
            caption: params[:caption],
            audio_name: params[:audio_name]
          }
        end

        def parse_stickers(stickers_param)
          return [] unless stickers_param.present?

          JSON.parse(stickers_param) rescue []
        end

        def generate_media_preview(media)
          return nil unless media

          {
            type: media.content_type&.start_with?('image/') ? 'image' : 'video',
            url: url_for(media),
            filename: media.original_filename
          }
        end

        def generate_video_preview(video)
          return nil unless video

          {
            url: url_for(video),
            filename: video.original_filename,
            duration: extract_video_duration(video),
            size: video.blob.byte_size
          }
        end

        def extract_video_duration(video)
          return 'Unknown' unless video.respond_to?(:blob)

          metadata = video.blob.metadata || {}
          duration = metadata['duration']

          if duration
            "#{duration.to_i}s"
          else
            'Unknown'
          end
        end

        def calculate_story_duration(story_data)
          # Stories are typically 15 seconds
          # Unless it's a video, then use actual duration
          if story_data[:media]&.content_type&.start_with?('video/')
            extract_video_duration(story_data[:media])
          else
            '15s'
          end
        end

        def count_interactive_elements(stickers)
          return 0 unless stickers.present?

          interactive_types = %w[poll question countdown quiz]
          stickers.count { |sticker| interactive_types.include?(sticker['sticker_type']) }
        end

        def calculate_estimated_reach(reel_data)
          # This would use ML/analytics to predict reach based on:
          # - Account follower count
          # - Historical performance
          # - Content analysis
          # - Hashtag analysis

          base_reach = @current_account.followers_count || 100

          # Simple estimation logic
          multiplier = 1.0
          multiplier += 0.3 if reel_data[:audio_name].present? # Trending audio
          multiplier += 0.2 if reel_data[:caption]&.include?('#') # Has hashtags
          multiplier += 0.1 if reel_data[:optimization_applied] # Caption optimized

          (base_reach * multiplier).to_i
        end

        def calculate_performance_score(reel_data)
          score = 50 # Base score

          # Add points for various factors
          score += 10 if reel_data[:caption].present?
          score += 15 if reel_data[:audio_name].present?
          score += 10 if reel_data[:caption]&.include?('#')
          score += 5 if reel_data[:cover_image].present?

          [score, 100].min
        end

        def load_story_analytics
          # Load story-specific analytics
          {
            total_stories: @current_account.social_media_posts.where(content_type: 'story').count,
            avg_reach: calculate_avg_reach_for_content('story'),
            avg_engagement: calculate_avg_engagement_for_content('story'),
            top_story_types: analyze_story_types
          }
        end

        def load_reel_analytics
          # Load reel-specific analytics
          {
            total_reels: @current_account.social_media_posts.where(content_type: 'reel').count,
            avg_reach: calculate_avg_reach_for_content('reel'),
            avg_engagement: calculate_avg_engagement_for_content('reel'),
            avg_watch_time: calculate_avg_watch_time,
            top_performing_reels: load_top_reels(5)
          }
        end

        def calculate_avg_reach_for_content(content_type)
          posts = @current_account.social_media_posts
                                 .where(content_type: content_type)
                                 .joins(:social_media_analytics)

          posts.any? ? posts.average('spree_social_media_analytics.reach').to_i : 0
        end

        def calculate_avg_engagement_for_content(content_type)
          posts = @current_account.social_media_posts
                                 .where(content_type: content_type)
                                 .joins(:social_media_analytics)

          posts.any? ? posts.average('spree_social_media_analytics.engagement').to_i : 0
        end

        def analyze_story_types
          # Analyze which story types perform best
          stories = @current_account.social_media_posts.where(content_type: 'story')

          type_performance = {}
          stories.each do |story|
            metadata = JSON.parse(story.metadata || '{}')
            story_type = metadata['story_type'] || 'standard'

            type_performance[story_type] ||= { count: 0, total_engagement: 0 }
            type_performance[story_type][:count] += 1
            type_performance[story_type][:total_engagement] += story.engagement_count || 0
          end

          type_performance.map do |type, data|
            {
              type: type,
              count: data[:count],
              avg_engagement: data[:count] > 0 ? (data[:total_engagement] / data[:count]) : 0
            }
          end.sort_by { |item| -item[:avg_engagement] }
        end

        def calculate_avg_watch_time
          # This would come from Instagram Insights API for reels
          'N/A' # Placeholder
        end

        def load_top_reels(limit)
          @current_account.social_media_posts
                         .where(content_type: 'reel')
                         .joins(:social_media_analytics)
                         .order('spree_social_media_analytics.engagement DESC')
                         .limit(limit)
        end

        def load_stories_vs_reels_comparison
          {
            reach_comparison: {
              stories: calculate_avg_reach_for_content('story'),
              reels: calculate_avg_reach_for_content('reel')
            },
            engagement_comparison: {
              stories: calculate_avg_engagement_for_content('story'),
              reels: calculate_avg_engagement_for_content('reel')
            },
            posting_frequency: {
              stories: calculate_posting_frequency('story'),
              reels: calculate_posting_frequency('reel')
            }
          }
        end

        def calculate_posting_frequency(content_type)
          posts = @current_account.social_media_posts
                                 .where(content_type: content_type)
                                 .where('created_at > ?', 30.days.ago)

          posts.count.to_f / 30 # Posts per day
        end

        def load_top_performing_content
          # Load top performing stories and reels combined
          @current_account.social_media_posts
                         .where(content_type: ['story', 'reel'])
                         .joins(:social_media_analytics)
                         .order('spree_social_media_analytics.engagement_rate DESC')
                         .limit(10)
        end

        def export_stories_reels_csv
          # Implementation for CSV export
          flash[:info] = 'CSV export feature coming soon!'
          redirect_back(fallback_location: analytics_admin_social_media_stories_and_reels_path)
        end

        def export_stories_reels_json
          # Implementation for JSON export
          flash[:info] = 'JSON export feature coming soon!'
          redirect_back(fallback_location: analytics_admin_social_media_stories_and_reels_path)
        end

        def perform_bulk_delete(content_ids)
          deleted_count = @current_account.social_media_posts
                                         .where(id: content_ids)
                                         .where(content_type: ['story', 'reel'])
                                         .destroy_all
                                         .length

          flash[:success] = "#{deleted_count} items deleted successfully"
        end

        def perform_bulk_archive(content_ids)
          archived_count = @current_account.social_media_posts
                                          .where(id: content_ids)
                                          .where(content_type: ['story', 'reel'])
                                          .update_all(status: 'archived')

          flash[:success] = "#{archived_count} items archived successfully"
        end
      end
    end
  end
end