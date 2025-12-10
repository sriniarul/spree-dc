module Spree
  class SocialMediaEngagementEvent < Spree::Base
    belongs_to :social_media_account, class_name: 'Spree::SocialMediaAccount'
    belongs_to :social_media_post, class_name: 'Spree::SocialMediaPost', optional: true

    validates :event_type, presence: true
    validates :occurred_at, presence: true

    scope :recent, -> { order(occurred_at: :desc) }
    scope :by_type, ->(type) { where(event_type: type) }
    scope :for_post, ->(post) { where(social_media_post: post) }
    scope :for_account, ->(account) { where(social_media_account: account) }
    scope :in_period, ->(start_date, end_date) { where(occurred_at: start_date..end_date) }

    # Event types
    EVENT_TYPES = %w[
      like unlike comment comment_delete share save unsave
      follow unfollow mention story_view story_tap_forward
      story_tap_back story_exit story_reply profile_visit
    ].freeze

    validates :event_type, inclusion: { in: EVENT_TYPES }

    def event_data_hash
      return {} unless event_data.present?

      JSON.parse(event_data)
    rescue JSON::ParserError
      {}
    end

    def positive_engagement?
      %w[like comment share save follow mention story_view profile_visit].include?(event_type)
    end

    def negative_engagement?
      %w[unlike comment_delete unsave unfollow story_exit].include?(event_type)
    end

    def neutral_engagement?
      !positive_engagement? && !negative_engagement?
    end

    def engagement_weight
      case event_type
      when 'like'
        1
      when 'comment'
        3
      when 'share'
        5
      when 'save'
        4
      when 'follow'
        10
      when 'mention'
        7
      when 'story_view'
        1
      when 'story_reply'
        6
      when 'profile_visit'
        2
      when 'unlike'
        -1
      when 'unfollow'
        -10
      when 'story_exit'
        -1
      else
        0
      end
    end

    def self.engagement_summary(account, period = 30.days)
      events = where(social_media_account: account)
                .where('occurred_at > ?', period.ago)

      total_events = events.count
      return {} if total_events.zero?

      {
        total_events: total_events,
        event_breakdown: events.group(:event_type).count,
        positive_events: events.select(&:positive_engagement?).count,
        negative_events: events.select(&:negative_engagement?).count,
        total_engagement_score: events.sum(&:engagement_weight),
        average_daily_events: (total_events.to_f / period.to_i.days).round(1),
        top_engaging_posts: top_engaging_posts(account, period, 5)
      }
    end

    def self.top_engaging_posts(account, period = 30.days, limit = 10)
      where(social_media_account: account)
        .where('occurred_at > ?', period.ago)
        .joins(:social_media_post)
        .group(:social_media_post_id)
        .select('social_media_post_id, COUNT(*) as event_count, SUM(CASE
          WHEN event_type = "like" THEN 1
          WHEN event_type = "comment" THEN 3
          WHEN event_type = "share" THEN 5
          WHEN event_type = "save" THEN 4
          ELSE 0 END) as engagement_score')
        .order('engagement_score DESC')
        .limit(limit)
        .includes(:social_media_post)
    end

    def self.daily_engagement_trend(account, days = 30)
      end_date = Date.current
      start_date = end_date - days.days

      daily_data = {}
      (start_date..end_date).each { |date| daily_data[date] = 0 }

      events = where(social_media_account: account)
                .where(occurred_at: start_date.beginning_of_day..end_date.end_of_day)
                .group('DATE(occurred_at)')
                .count

      events.each do |date_string, count|
        date = Date.parse(date_string)
        daily_data[date] = count
      end

      daily_data.map { |date, count| { date: date, count: count } }
    end

    def self.engagement_by_content_type(account, period = 30.days)
      events = joins(:social_media_post)
                .where(social_media_account: account)
                .where('occurred_at > ?', period.ago)

      return {} if events.empty?

      events.joins(:social_media_post)
           .group('spree_social_media_posts.content_type')
           .group(:event_type)
           .count
    end

    def self.peak_engagement_times(account, period = 30.days)
      events = where(social_media_account: account)
                .where('occurred_at > ?', period.ago)

      return {} if events.empty?

      # Group by hour of day
      hourly_engagement = events.group('EXTRACT(hour FROM occurred_at)').count

      # Group by day of week (0 = Sunday)
      daily_engagement = events.group('EXTRACT(dow FROM occurred_at)').count

      {
        hourly_distribution: hourly_engagement,
        daily_distribution: daily_engagement,
        peak_hour: hourly_engagement.max_by { |hour, count| count }&.first,
        peak_day: daily_engagement.max_by { |day, count| count }&.first
      }
    end

    def self.user_engagement_patterns(account, limit = 50)
      # Analyze patterns of specific users who engage frequently
      frequent_engagers = where(social_media_account: account)
                           .where('occurred_at > ?', 30.days.ago)
                           .where.not(user_id: nil)
                           .group(:user_id)
                           .having('COUNT(*) > ?', 3)
                           .count
                           .sort_by { |user_id, count| -count }
                           .first(limit)

      patterns = frequent_engagers.map do |user_id, total_engagements|
        user_events = where(social_media_account: account, user_id: user_id)
                       .where('occurred_at > ?', 30.days.ago)

        engagement_types = user_events.group(:event_type).count
        engagement_score = user_events.sum(&:engagement_weight)

        {
          user_id: user_id,
          total_engagements: total_engagements,
          engagement_types: engagement_types,
          engagement_score: engagement_score,
          most_common_action: engagement_types.max_by { |type, count| count }&.first,
          loyalty_score: calculate_user_loyalty_score(user_events)
        }
      end

      patterns
    end

    def self.engagement_velocity(account, post)
      # Calculate how quickly a post gains engagement after publishing
      return {} unless post.published_at

      events = where(social_media_account: account, social_media_post: post)
                .order(:occurred_at)

      return {} if events.empty?

      publish_time = post.published_at
      velocity_data = []

      # Calculate cumulative engagement over time
      cumulative_count = 0
      cumulative_score = 0

      events.each do |event|
        minutes_since_publish = ((event.occurred_at - publish_time) / 1.minute).to_i
        cumulative_count += 1
        cumulative_score += event.engagement_weight

        velocity_data << {
          minutes: minutes_since_publish,
          cumulative_events: cumulative_count,
          cumulative_score: cumulative_score,
          event_type: event.event_type
        }
      end

      # Calculate engagement rate for different time periods
      {
        velocity_data: velocity_data,
        first_hour_events: events.where('occurred_at <= ?', publish_time + 1.hour).count,
        first_day_events: events.where('occurred_at <= ?', publish_time + 1.day).count,
        first_week_events: events.where('occurred_at <= ?', publish_time + 1.week).count,
        peak_velocity_period: calculate_peak_velocity_period(velocity_data)
      }
    end

    private

    def self.calculate_user_loyalty_score(user_events)
      # Calculate a loyalty score based on engagement patterns
      total_events = user_events.count
      return 0 if total_events.zero?

      # Factors that increase loyalty score
      positive_actions = user_events.select(&:positive_engagement?).count
      engagement_span = (user_events.maximum(:occurred_at) - user_events.minimum(:occurred_at)) / 1.day
      consistency = total_events / [engagement_span, 1].max

      # Base score from positive engagement ratio
      base_score = (positive_actions.to_f / total_events * 50).round

      # Bonus for consistency
      consistency_bonus = [consistency * 10, 25].min

      # Bonus for engagement variety
      variety_bonus = [user_events.group(:event_type).count.keys.length * 5, 25].min

      (base_score + consistency_bonus + variety_bonus).round
    end

    def self.calculate_peak_velocity_period(velocity_data)
      return nil if velocity_data.length < 2

      max_velocity = 0
      peak_start = 0
      peak_end = 0

      (0...velocity_data.length - 1).each do |i|
        current_data = velocity_data[i]
        next_data = velocity_data[i + 1]

        time_diff = next_data[:minutes] - current_data[:minutes]
        next if time_diff.zero?

        events_diff = next_data[:cumulative_events] - current_data[:cumulative_events]
        velocity = events_diff.to_f / time_diff

        if velocity > max_velocity
          max_velocity = velocity
          peak_start = current_data[:minutes]
          peak_end = next_data[:minutes]
        end
      end

      {
        start_minutes: peak_start,
        end_minutes: peak_end,
        velocity: max_velocity,
        description: "#{peak_start}-#{peak_end} minutes after posting"
      }
    end
  end
end