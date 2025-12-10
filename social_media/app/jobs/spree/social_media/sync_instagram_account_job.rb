module Spree
  module SocialMedia
    class SyncInstagramAccountJob < ApplicationJob
      queue_as :social_media_sync

      retry_on StandardError, wait: :exponentially_longer, attempts: 5

      def perform(account_id)
        @account = Spree::SocialMediaAccount.find(account_id)
        @vendor = @account.vendor

        Rails.logger.info "Syncing Instagram account #{@account.username} (ID: #{account_id})"

        return unless @account.active? && @account.platform == 'instagram'

        begin
          # Sync account profile information
          sync_account_profile

          # Sync recent posts if configured
          sync_recent_posts if should_sync_posts?

          # Sync account analytics
          sync_account_analytics if should_sync_analytics?

          # Sync followers data
          sync_followers_data if should_sync_followers?

          # Sync story highlights
          sync_story_highlights if should_sync_stories?

          # Update last sync timestamp
          @account.update!(last_synced_at: Time.current)

          Rails.logger.info "Successfully synced Instagram account #{@account.username}"

        rescue => e
          Rails.logger.error "Failed to sync Instagram account #{@account.username}: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")

          # Update sync status with error
          @account.update!(
            last_sync_error: e.message,
            last_sync_attempted_at: Time.current
          )

          raise
        end
      end

      private

      def sync_account_profile
        service = Spree::SocialMedia::InstagramApiService.new(@account.access_token)

        profile_data = service.get_account_info(@account.platform_account_id)

        if profile_data[:success]
          account_info = profile_data[:data]

          @account.update!(
            username: account_info['username'],
            display_name: account_info['name'],
            bio: account_info['biography'],
            website_url: account_info['website'],
            profile_picture_url: account_info['profile_picture_url'],
            followers_count: account_info['followers_count'],
            following_count: account_info['follows_count'],
            posts_count: account_info['media_count'],
            account_type: account_info['account_type'],
            is_verified: account_info['is_verified'] || false,
            is_business_account: account_info['account_type'] == 'BUSINESS',
            platform_data: account_info.to_json
          )

          Rails.logger.info "Updated profile information for #{@account.username}"
        else
          Rails.logger.error "Failed to fetch profile data: #{profile_data[:error]}"
        end
      end

      def sync_recent_posts
        service = Spree::SocialMedia::InstagramApiService.new(@account.access_token)

        # Get posts from the last sync or last 30 days
        since = @account.last_synced_at || 30.days.ago

        posts_data = service.get_user_media(
          @account.platform_account_id,
          limit: 50,
          since: since
        )

        if posts_data[:success]
          posts = posts_data[:data]

          posts.each do |post_data|
            sync_individual_post(post_data)
          end

          Rails.logger.info "Synced #{posts.length} posts for #{@account.username}"
        else
          Rails.logger.error "Failed to fetch posts: #{posts_data[:error]}"
        end
      end

      def sync_individual_post(post_data)
        # Find or create post record
        post = @account.social_media_posts.find_or_initialize_by(
          platform_post_id: post_data['id']
        )

        # Update post information
        post.assign_attributes(
          content_type: map_media_type(post_data['media_type']),
          caption: post_data['caption'],
          media_url: post_data['media_url'],
          permalink: post_data['permalink'],
          thumbnail_url: post_data['thumbnail_url'],
          likes_count: post_data.dig('insights', 'likes') || 0,
          comments_count: post_data.dig('insights', 'comments') || 0,
          shares_count: post_data.dig('insights', 'shares') || 0,
          saves_count: post_data.dig('insights', 'saves') || 0,
          reach: post_data.dig('insights', 'reach') || 0,
          impressions: post_data.dig('insights', 'impressions') || 0,
          status: 'published',
          published_at: Time.parse(post_data['timestamp']),
          platform_data: post_data.to_json,
          synced_at: Time.current
        )

        post.save!

        # Queue job to sync post analytics
        if post_data.dig('insights')
          Spree::SocialMedia::SyncPostAnalyticsJob.perform_later(post.id, post_data['insights'])
        end

        # Extract and save hashtags if present
        extract_hashtags_from_caption(post) if post.caption.present?

        post
      end

      def sync_account_analytics
        service = Spree::SocialMedia::InstagramApiService.new(@account.access_token)

        # Get insights for the last 30 days
        end_date = Date.current
        start_date = end_date - 29.days

        insights_data = service.get_account_insights(
          @account.platform_account_id,
          metrics: %w[impressions reach profile_views website_clicks],
          period: 'day',
          since: start_date,
          until: end_date
        )

        if insights_data[:success]
          insights = insights_data[:data]

          # Process daily insights
          insights.each do |daily_insight|
            date = Date.parse(daily_insight['end_time'])

            analytics = @account.social_media_analytics.find_or_create_by(date: date)

            analytics.update!(
              impressions: daily_insight.dig('values', 0, 'value') || 0,
              reach: daily_insight.dig('values', 1, 'value') || 0,
              profile_views: daily_insight.dig('values', 2, 'value') || 0,
              website_clicks: daily_insight.dig('values', 3, 'value') || 0,
              raw_data: daily_insight.to_json,
              synced_at: Time.current
            )
          end

          Rails.logger.info "Synced analytics for #{@account.username}"
        else
          Rails.logger.error "Failed to fetch analytics: #{insights_data[:error]}"
        end
      end

      def sync_followers_data
        service = Spree::SocialMedia::InstagramApiService.new(@account.access_token)

        # Get follower insights (demographics)
        demographics_data = service.get_audience_insights(
          @account.platform_account_id,
          metrics: %w[audience_gender_age audience_city audience_country]
        )

        if demographics_data[:success]
          demographics = demographics_data[:data]

          # Create or update audience demographics record
          audience_demo = @account.audience_demographics || @account.build_audience_demographics

          audience_demo.update!(
            gender_age_data: demographics.dig('audience_gender_age', 'values', 0, 'value'),
            city_data: demographics.dig('audience_city', 'values', 0, 'value'),
            country_data: demographics.dig('audience_country', 'values', 0, 'value'),
            raw_data: demographics.to_json,
            synced_at: Time.current
          )

          Rails.logger.info "Synced audience demographics for #{@account.username}"
        else
          Rails.logger.error "Failed to fetch audience insights: #{demographics_data[:error]}"
        end
      end

      def sync_story_highlights
        service = Spree::SocialMedia::InstagramApiService.new(@account.access_token)

        highlights_data = service.get_story_highlights(@account.platform_account_id)

        if highlights_data[:success]
          highlights = highlights_data[:data]

          highlights.each do |highlight_data|
            sync_story_highlight(highlight_data)
          end

          Rails.logger.info "Synced #{highlights.length} story highlights for #{@account.username}"
        else
          Rails.logger.error "Failed to fetch story highlights: #{highlights_data[:error]}"
        end
      end

      def sync_story_highlight(highlight_data)
        highlight = @account.story_highlights.find_or_initialize_by(
          platform_highlight_id: highlight_data['id']
        )

        highlight.assign_attributes(
          title: highlight_data['title'],
          cover_media_url: highlight_data['cover_media_url'],
          stories_count: highlight_data['media_count'] || 0,
          platform_data: highlight_data.to_json,
          synced_at: Time.current
        )

        highlight.save!
      end

      def extract_hashtags_from_caption(post)
        return unless post.caption.present?

        hashtags = post.caption.scan(/#\w+/)
        return if hashtags.empty?

        # Create hashtag usage records
        hashtags.each do |hashtag|
          hashtag_clean = hashtag.downcase.gsub('#', '')

          hashtag_record = Spree::Hashtag.find_or_create_by(
            name: hashtag_clean,
            vendor: @vendor
          )

          # Create usage record
          Spree::HashtagUsage.find_or_create_by(
            hashtag: hashtag_record,
            social_media_post: post,
            used_at: post.published_at || Time.current
          )
        end
      end

      def should_sync_posts?
        sync_settings = @vendor.social_media_sync_settings || {}
        sync_settings.fetch('sync_posts', true)
      end

      def should_sync_analytics?
        sync_settings = @vendor.social_media_sync_settings || {}
        sync_settings.fetch('sync_analytics', true)
      end

      def should_sync_followers?
        sync_settings = @vendor.social_media_sync_settings || {}
        sync_settings.fetch('sync_followers', false) # Disabled by default (API limitations)
      end

      def should_sync_stories?
        sync_settings = @vendor.social_media_sync_settings || {}
        sync_settings.fetch('sync_stories', true)
      end

      def map_media_type(instagram_type)
        case instagram_type
        when 'IMAGE'
          'post'
        when 'VIDEO'
          'reel'
        when 'CAROUSEL_ALBUM'
          'carousel'
        else
          'post'
        end
      end
    end
  end
end