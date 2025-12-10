module Spree
  module SocialMedia
    class PostScheduler
      include Rails.application.routes.url_helpers

      attr_reader :vendor, :errors, :warnings

      # Optimal posting times (in hours, 24-hour format)
      OPTIMAL_TIMES = {
        instagram: {
          weekdays: [9, 11, 13, 17, 19], # 9 AM, 11 AM, 1 PM, 5 PM, 7 PM
          weekends: [10, 12, 14, 16, 18]  # 10 AM, 12 PM, 2 PM, 4 PM, 6 PM
        },
        facebook: {
          weekdays: [9, 13, 15, 19, 21],  # 9 AM, 1 PM, 3 PM, 7 PM, 9 PM
          weekends: [10, 13, 15, 19, 20]  # 10 AM, 1 PM, 3 PM, 7 PM, 8 PM
        },
        youtube: {
          weekdays: [14, 16, 18, 20],     # 2 PM, 4 PM, 6 PM, 8 PM
          weekends: [11, 14, 16, 19]      # 11 AM, 2 PM, 4 PM, 7 PM
        }
      }.freeze

      # Maximum posts per day per platform
      MAX_POSTS_PER_DAY = {
        instagram: 5,
        facebook: 8,
        youtube: 3,
        tiktok: 4
      }.freeze

      def initialize(vendor)
        @vendor = vendor
        @errors = []
        @warnings = []
      end

      def schedule_post(post_params, scheduling_options = {})
        post = build_post(post_params)
        return false unless post.valid?

        scheduling_time = determine_scheduling_time(post, scheduling_options)

        if scheduling_time
          post.scheduled_at = scheduling_time
          post.status = 'scheduled'

          if post.save
            schedule_background_job(post)
            true
          else
            @errors.concat(post.errors.full_messages)
            false
          end
        else
          false
        end
      end

      def bulk_schedule(posts_params, scheduling_strategy = 'optimal')
        results = []

        posts_params.each_with_index do |post_params, index|
          post = build_post(post_params)

          if post.valid?
            case scheduling_strategy
            when 'optimal'
              schedule_time = find_next_optimal_time(post.social_media_account.platform, index)
            when 'spread'
              schedule_time = spread_posts_evenly(index, posts_params.size)
            when 'immediate'
              schedule_time = (index * 5).minutes.from_now # 5 minute intervals
            else
              schedule_time = determine_custom_schedule(post_params, scheduling_strategy)
            end

            post.scheduled_at = schedule_time
            post.status = 'scheduled'

            if post.save
              schedule_background_job(post)
              results << { success: true, post: post, scheduled_at: schedule_time }
            else
              results << { success: false, errors: post.errors.full_messages }
            end
          else
            results << { success: false, errors: post.errors.full_messages }
          end
        end

        results
      end

      def reschedule_post(post_id, new_time)
        post = @vendor.social_media_posts.find(post_id)

        return false unless can_reschedule?(post)

        # Cancel existing scheduled job
        cancel_scheduled_job(post) if post.scheduled_at

        # Validate new scheduling time
        unless valid_scheduling_time?(new_time, post.social_media_account.platform)
          @errors << "Invalid scheduling time: #{new_time}"
          return false
        end

        post.scheduled_at = new_time
        post.status = 'scheduled'

        if post.save
          schedule_background_job(post)
          true
        else
          @errors.concat(post.errors.full_messages)
          false
        end
      end

      def cancel_scheduled_post(post_id)
        post = @vendor.social_media_posts.find(post_id)

        return false unless can_cancel_schedule?(post)

        cancel_scheduled_job(post)

        post.scheduled_at = nil
        post.status = 'draft'

        post.save
      end

      def get_scheduling_suggestions(platform, content_type = 'feed', timezone = 'UTC')
        suggestions = []
        optimal_times = OPTIMAL_TIMES[platform.to_sym] || OPTIMAL_TIMES[:instagram]

        # Get next 7 days
        (0..6).each do |day_offset|
          date = day_offset.days.from_now.in_time_zone(timezone).to_date
          is_weekend = date.saturday? || date.sunday?

          times = is_weekend ? optimal_times[:weekends] : optimal_times[:weekdays]

          times.each do |hour|
            suggested_time = date.in_time_zone(timezone).beginning_of_day + hour.hours

            # Skip past times
            next if suggested_time <= Time.current

            # Check if slot is available (not too many posts scheduled)
            if slot_available?(platform, suggested_time)
              engagement_score = calculate_engagement_score(platform, suggested_time, content_type)

              suggestions << {
                datetime: suggested_time,
                day_name: suggested_time.strftime('%A'),
                time_display: suggested_time.strftime('%I:%M %p'),
                engagement_score: engagement_score,
                competition_level: get_competition_level(platform, suggested_time),
                recommended: engagement_score > 75
              }
            end
          end
        end

        # Sort by engagement score (highest first)
        suggestions.sort_by { |s| -s[:engagement_score] }.first(20)
      end

      def analyze_posting_schedule(date_range = 30.days.ago..Date.current)
        posts = @vendor.social_media_posts
                       .where(published_at: date_range)
                       .includes(:social_media_account)

        analysis = {
          total_posts: posts.count,
          posts_by_platform: {},
          posts_by_hour: Hash.new(0),
          posts_by_day: Hash.new(0),
          average_engagement: {},
          optimal_times_used: 0,
          recommendations: []
        }

        posts.each do |post|
          platform = post.social_media_account.platform
          published_time = post.published_at

          # Count by platform
          analysis[:posts_by_platform][platform] ||= 0
          analysis[:posts_by_platform][platform] += 1

          # Count by hour and day
          analysis[:posts_by_hour][published_time.hour] += 1
          analysis[:posts_by_day][published_time.strftime('%A')] += 1

          # Check if posted at optimal time
          if optimal_time?(platform, published_time)
            analysis[:optimal_times_used] += 1
          end

          # Calculate engagement if available
          if post.engagement_count && post.engagement_count > 0
            analysis[:average_engagement][platform] ||= []
            analysis[:average_engagement][platform] << post.engagement_count
          end
        end

        # Calculate average engagement
        analysis[:average_engagement].each do |platform, engagements|
          analysis[:average_engagement][platform] = engagements.sum.to_f / engagements.size
        end

        # Generate recommendations
        analysis[:recommendations] = generate_schedule_recommendations(analysis)

        analysis
      end

      def get_schedule_conflicts(start_date, end_date)
        conflicts = []

        # Check for too many posts on same day
        posts_by_date = @vendor.social_media_posts
                              .scheduled
                              .where(scheduled_at: start_date..end_date)
                              .group_by { |post| post.scheduled_at.to_date }

        posts_by_date.each do |date, posts|
          platform_counts = posts.group_by { |p| p.social_media_account.platform }

          platform_counts.each do |platform, platform_posts|
            max_allowed = MAX_POSTS_PER_DAY[platform.to_sym] || 5

            if platform_posts.size > max_allowed
              conflicts << {
                type: 'daily_limit_exceeded',
                date: date,
                platform: platform,
                scheduled_count: platform_posts.size,
                max_allowed: max_allowed,
                posts: platform_posts.map(&:id)
              }
            end
          end

          # Check for posts scheduled too close together (within 1 hour)
          time_sorted_posts = posts.sort_by(&:scheduled_at)
          time_sorted_posts.each_with_index do |post, index|
            next_post = time_sorted_posts[index + 1]
            next unless next_post

            time_diff = (next_post.scheduled_at - post.scheduled_at) / 1.hour

            if time_diff < 1 && post.social_media_account.platform == next_post.social_media_account.platform
              conflicts << {
                type: 'posts_too_close',
                platform: post.social_media_account.platform,
                post1_id: post.id,
                post2_id: next_post.id,
                time_difference_minutes: (time_diff * 60).round,
                scheduled_times: [post.scheduled_at, next_post.scheduled_at]
              }
            end
          end
        end

        conflicts
      end

      private

      def build_post(post_params)
        post = @vendor.social_media_posts.build(post_params)
        post.status = 'draft' # Will be changed to 'scheduled' if scheduling succeeds
        post
      end

      def determine_scheduling_time(post, options)
        platform = post.social_media_account.platform

        case options[:strategy]&.to_sym
        when :immediate
          5.minutes.from_now
        when :next_optimal
          find_next_optimal_time(platform)
        when :custom
          options[:datetime]&.to_time
        when :queue
          find_next_available_slot(platform)
        else
          # Default: next optimal time
          find_next_optimal_time(platform)
        end
      end

      def find_next_optimal_time(platform, offset_hours = 0)
        optimal_times = OPTIMAL_TIMES[platform.to_sym] || OPTIMAL_TIMES[:instagram]
        current_time = Time.current + offset_hours.hours

        # Look for next optimal time in the next 7 days
        (0..6).each do |day_offset|
          check_date = (current_time + day_offset.days).to_date
          is_weekend = check_date.saturday? || check_date.sunday?

          times = is_weekend ? optimal_times[:weekends] : optimal_times[:weekdays]

          times.each do |hour|
            potential_time = check_date.in_time_zone.beginning_of_day + hour.hours

            # Skip if time has passed or is too close
            next if potential_time <= current_time + 1.hour

            # Check if slot is available
            if slot_available?(platform, potential_time)
              return potential_time
            end
          end
        end

        # Fallback: schedule for tomorrow at 9 AM
        1.day.from_now.beginning_of_day + 9.hours
      end

      def find_next_available_slot(platform)
        current_time = Time.current

        # Check every hour for the next 48 hours
        (1..48).each do |hour_offset|
          check_time = current_time + hour_offset.hours

          # Skip overnight hours (11 PM to 7 AM)
          next if check_time.hour >= 23 || check_time.hour < 7

          if slot_available?(platform, check_time)
            return check_time
          end
        end

        # Fallback
        24.hours.from_now
      end

      def spread_posts_evenly(index, total_posts)
        # Spread posts evenly over the next week
        base_time = Time.current + 1.hour
        interval = 7.days / total_posts

        base_time + (interval * index)
      end

      def slot_available?(platform, time)
        # Check if there are already too many posts scheduled at this time
        start_time = time - 30.minutes
        end_time = time + 30.minutes

        existing_posts = @vendor.social_media_posts
                               .joins(:social_media_account)
                               .where(social_media_accounts: { platform: platform })
                               .where(scheduled_at: start_time..end_time)
                               .count

        existing_posts < 2 # Maximum 2 posts per hour per platform
      end

      def calculate_engagement_score(platform, time, content_type)
        base_score = 50
        hour = time.hour
        day_of_week = time.wday

        # Hour-based scoring
        optimal_hours = OPTIMAL_TIMES[platform.to_sym]
        if optimal_hours
          current_day_times = (day_of_week == 0 || day_of_week == 6) ?
                             optimal_hours[:weekends] : optimal_hours[:weekdays]

          if current_day_times.include?(hour)
            base_score += 30
          elsif current_day_times.any? { |h| (h - hour).abs <= 1 }
            base_score += 15
          end
        end

        # Day-based scoring
        case day_of_week
        when 1, 2, 3, 4  # Monday to Thursday
          base_score += 10
        when 5           # Friday
          base_score += 5
        when 6, 0        # Saturday, Sunday
          base_score -= 5 if platform == 'linkedin'
        end

        # Content type adjustments
        case content_type
        when 'story'
          base_score += 5 if hour >= 18 && hour <= 22 # Stories perform better in evenings
        when 'reel'
          base_score += 10 if hour >= 19 && hour <= 21 # Reels peak in early evening
        end

        [base_score, 100].min
      end

      def get_competition_level(platform, time)
        hour = time.hour

        case platform.to_sym
        when :instagram
          if hour >= 19 && hour <= 21
            'high'
          elsif hour >= 9 && hour <= 11
            'medium'
          else
            'low'
          end
        else
          'medium'
        end
      end

      def optimal_time?(platform, time)
        optimal_times = OPTIMAL_TIMES[platform.to_sym]
        return false unless optimal_times

        hour = time.hour
        is_weekend = time.saturday? || time.sunday?

        relevant_times = is_weekend ? optimal_times[:weekends] : optimal_times[:weekdays]
        relevant_times.include?(hour)
      end

      def schedule_background_job(post)
        # Schedule the publish job for the specified time
        Spree::SocialMedia::PublishPostJob.perform_at(post.scheduled_at, post.id)
      end

      def cancel_scheduled_job(post)
        # This would depend on your background job system (Sidekiq, DelayedJob, etc.)
        # For Sidekiq with sidekiq-cron or similar:
        # Sidekiq::Queue.new.each do |job|
        #   job.delete if job.args.include?(post.id)
        # end

        Rails.logger.info "Cancelled scheduled job for post #{post.id}"
      end

      def can_reschedule?(post)
        post.scheduled? && post.scheduled_at > Time.current
      end

      def can_cancel_schedule?(post)
        post.scheduled? && post.scheduled_at > Time.current
      end

      def valid_scheduling_time?(time, platform)
        return false if time <= Time.current

        # Instagram Stories cannot be scheduled
        return false if platform == 'instagram' && @post&.content_type == 'story'

        # Cannot schedule more than 75 days in advance
        return false if time > 75.days.from_now

        true
      end

      def generate_schedule_recommendations(analysis)
        recommendations = []

        # Check if posting at optimal times
        optimal_percentage = (analysis[:optimal_times_used].to_f / analysis[:total_posts] * 100).round(1)
        if optimal_percentage < 50
          recommendations << {
            type: 'timing',
            message: "Only #{optimal_percentage}% of posts were published at optimal times. Consider scheduling posts during peak engagement hours.",
            priority: 'high'
          }
        end

        # Check posting frequency
        posts_per_day = analysis[:total_posts].to_f / 30
        if posts_per_day < 1
          recommendations << {
            type: 'frequency',
            message: "Posting frequency is low (#{posts_per_day.round(1)} posts/day). Consider increasing to 1-2 posts daily for better engagement.",
            priority: 'medium'
          }
        elsif posts_per_day > 3
          recommendations << {
            type: 'frequency',
            message: "Posting frequency is high (#{posts_per_day.round(1)} posts/day). Consider reducing to avoid audience fatigue.",
            priority: 'medium'
          }
        end

        # Check platform distribution
        if analysis[:posts_by_platform].size == 1
          recommendations << {
            type: 'diversity',
            message: "Consider diversifying across multiple social media platforms to reach a wider audience.",
            priority: 'low'
          }
        end

        recommendations
      end
    end
  end
end