module Spree
  class SocialMediaWebhookEvent < Spree::Base
    belongs_to :social_media_account, class_name: 'Spree::SocialMediaAccount'

    validates :event_type, presence: true
    validates :occurred_at, presence: true

    scope :recent, -> { order(occurred_at: :desc) }
    scope :unprocessed, -> { where(processed: false) }
    scope :processed, -> { where(processed: true) }
    scope :by_type, ->(type) { where(event_type: type) }
    scope :by_platform, ->(platform) { joins(:social_media_account).where(spree_social_media_accounts: { platform: platform }) }
    scope :in_period, ->(start_date, end_date) { where(occurred_at: start_date..end_date) }

    # Event types
    EVENT_TYPES = %w[
      comment like unlike share save unsave follow unfollow
      mention story_view story_reply direct_message
      post_created post_updated post_deleted
      unknown error
    ].freeze

    validates :event_type, inclusion: { in: EVENT_TYPES }

    before_save :set_processing_priority
    after_create :queue_processing_job, if: :should_auto_process?

    def event_data_hash
      return {} unless event_data.present?

      JSON.parse(event_data)
    rescue JSON::ParserError
      {}
    end

    def mark_as_processed!(result = nil)
      update!(
        processed: true,
        processed_at: Time.current,
        processing_result: result&.to_json
      )
    end

    def mark_as_failed!(error_message)
      update!(
        processed: false,
        processing_attempts: (processing_attempts || 0) + 1,
        last_error: error_message,
        last_attempted_at: Time.current
      )
    end

    def processing_result_hash
      return {} unless processing_result.present?

      JSON.parse(processing_result)
    rescue JSON::ParserError
      {}
    end

    def high_priority?
      priority_level == 'high'
    end

    def requires_immediate_attention?
      event_type.in?(%w[error direct_message mention]) || high_priority?
    end

    def retry_processing?
      !processed && (processing_attempts || 0) < max_retry_attempts &&
      (last_attempted_at.nil? || last_attempted_at < retry_delay.ago)
    end

    def max_retry_attempts
      case event_type
      when 'error'
        1 # Don't retry error events
      when 'direct_message', 'mention'
        5 # High priority events get more retries
      else
        3 # Standard retry limit
      end
    end

    def retry_delay
      base_delay = case processing_attempts || 0
                  when 0..1
                    5.minutes
                  when 2..3
                    30.minutes
                  else
                    2.hours
                  end

      # Add jitter to prevent thundering herd
      base_delay + rand(0..60).seconds
    end

    def self.processing_stats(period = 24.hours)
      events = where('occurred_at > ?', period.ago)

      total_events = events.count
      return {} if total_events.zero?

      processed_events = events.processed.count
      failed_events = events.where('processing_attempts > 0 AND processed = false').count
      pending_events = events.unprocessed.where('processing_attempts IS NULL OR processing_attempts = 0').count

      {
        total_events: total_events,
        processed_events: processed_events,
        failed_events: failed_events,
        pending_events: pending_events,
        success_rate: (processed_events.to_f / total_events * 100).round(1),
        events_by_type: events.group(:event_type).count,
        events_by_priority: events.group(:priority_level).count,
        average_processing_time: calculate_average_processing_time(events.processed)
      }
    end

    def self.failed_events_for_retry
      where(processed: false)
        .where.not(processing_attempts: nil)
        .where('processing_attempts > 0')
        .where('processing_attempts < ?', 5)
        .select(&:retry_processing?)
    end

    def self.events_requiring_attention
      where(processed: false)
        .where(priority_level: 'high')
        .or(where(event_type: %w[error direct_message mention]))
        .order(:occurred_at)
    end

    def self.webhook_health_check(period = 1.hour)
      recent_events = where('occurred_at > ?', period.ago)

      return { status: 'healthy', message: 'No recent webhook activity' } if recent_events.empty?

      total_events = recent_events.count
      error_events = recent_events.where(event_type: 'error').count
      failed_processing = recent_events.where('processing_attempts > 2 AND processed = false').count

      error_rate = (error_events.to_f / total_events * 100).round(1)
      failure_rate = (failed_processing.to_f / total_events * 100).round(1)

      if error_rate > 10 || failure_rate > 5
        {
          status: 'unhealthy',
          message: "High error rate: #{error_rate}% errors, #{failure_rate}% processing failures",
          error_rate: error_rate,
          failure_rate: failure_rate,
          total_events: total_events
        }
      elsif error_rate > 5 || failure_rate > 2
        {
          status: 'warning',
          message: "Elevated error rate: #{error_rate}% errors, #{failure_rate}% processing failures",
          error_rate: error_rate,
          failure_rate: failure_rate,
          total_events: total_events
        }
      else
        {
          status: 'healthy',
          message: 'Webhook processing is operating normally',
          error_rate: error_rate,
          failure_rate: failure_rate,
          total_events: total_events
        }
      end
    end

    def self.cleanup_old_events(days_to_keep = 90)
      cutoff_date = days_to_keep.days.ago

      # Keep error events longer for debugging
      old_regular_events = where('occurred_at < ? AND event_type != ?', cutoff_date, 'error')
      old_error_events = where('occurred_at < ? AND event_type = ?', (days_to_keep * 2).days.ago, 'error')

      deleted_count = 0
      deleted_count += old_regular_events.delete_all
      deleted_count += old_error_events.delete_all

      Rails.logger.info "Cleaned up #{deleted_count} old webhook events"
      deleted_count
    end

    def self.event_volume_by_hour(date = Date.current)
      start_time = date.beginning_of_day
      end_time = date.end_of_day

      events = where(occurred_at: start_time..end_time)

      hourly_data = {}
      (0..23).each { |hour| hourly_data[hour] = 0 }

      events.group('EXTRACT(hour FROM occurred_at)').count.each do |hour, count|
        hourly_data[hour.to_i] = count
      end

      hourly_data.map { |hour, count| { hour: hour, count: count } }
    end

    private

    def set_processing_priority
      self.priority_level ||= determine_priority
    end

    def determine_priority
      case event_type
      when 'error'
        'critical'
      when 'direct_message', 'mention'
        'high'
      when 'comment', 'story_reply'
        'medium'
      when 'like', 'follow', 'story_view'
        'low'
      else
        'low'
      end
    end

    def should_auto_process?
      !event_type.in?(%w[error unknown]) && priority_level != 'critical'
    end

    def queue_processing_job
      case event_type
      when 'comment'
        Spree::SocialMedia::ProcessWebhookEventJob.perform_later(id, 'comment')
      when 'direct_message'
        Spree::SocialMedia::ProcessWebhookEventJob.perform_later(id, 'message')
      when 'mention'
        Spree::SocialMedia::ProcessWebhookEventJob.perform_later(id, 'mention')
      when 'like', 'unlike', 'follow', 'unfollow'
        Spree::SocialMedia::ProcessWebhookEventJob.perform_later(id, 'engagement')
      else
        Spree::SocialMedia::ProcessWebhookEventJob.perform_later(id, 'general')
      end
    end

    def self.calculate_average_processing_time(processed_events)
      return 0 if processed_events.empty?

      processing_times = processed_events.where.not(processed_at: nil).map do |event|
        next 0 unless event.processed_at && event.occurred_at
        (event.processed_at - event.occurred_at) / 1.second
      end.compact

      return 0 if processing_times.empty?

      (processing_times.sum / processing_times.length).round(2)
    end
  end
end