module Spree
  class SocialMediaMessage < Spree::Base
    belongs_to :social_media_account, class_name: 'Spree::SocialMediaAccount'

    validates :platform_message_id, presence: true, uniqueness: { scope: :social_media_account_id }
    validates :sender_id, presence: true
    validates :message_type, presence: true

    scope :recent, -> { order(received_at: :desc) }
    scope :unread, -> { where(read: false) }
    scope :by_type, ->(type) { where(message_type: type) }
    scope :from_sender, ->(sender_id) { where(sender_id: sender_id) }

    # Message types
    MESSAGE_TYPES = %w[direct_message story_reply comment_reply automated_message].freeze

    validates :message_type, inclusion: { in: MESSAGE_TYPES }

    before_save :analyze_message_content
    before_save :determine_priority

    def metadata_hash
      return {} unless metadata.present?

      JSON.parse(metadata)
    rescue JSON::ParserError
      {}
    end

    def mark_as_read!
      update!(read: true, read_at: Time.current)
    end

    def requires_response?
      return false if message_type == 'automated_message'

      priority_level == 'high' || contains_question? || contains_complaint?
    end

    def contains_question?
      return false unless message_text.present?

      message_text.include?('?') ||
      message_text.match?(/\b(what|how|when|where|why|which|can|could|would|should)\b/i)
    end

    def contains_complaint?
      return false unless message_text.present?

      complaint_keywords = %w[problem issue complaint bad terrible awful disappointed refund help support]
      complaint_keywords.any? { |keyword| message_text.downcase.include?(keyword) }
    end

    def sentiment_label
      case sentiment_score
      when 0.6..1.0
        'positive'
      when 0.4..0.59
        'neutral'
      when 0..0.39
        'negative'
      else
        'unknown'
      end
    end

    def generate_auto_reply_suggestions
      suggestions = []

      if contains_question?
        suggestions = [
          "Thanks for your message! We'll get back to you with more details soon.",
          "Great question! Our team will respond with the information you need.",
          "We appreciate you reaching out! We'll have an answer for you shortly."
        ]
      elsif contains_complaint?
        suggestions = [
          "We're sorry to hear about this issue. Our team will reach out to help resolve this immediately.",
          "Thank you for bringing this to our attention. We want to make this right - we'll contact you shortly.",
          "We apologize for any inconvenience. Our customer service team will be in touch to assist you."
        ]
      elsif sentiment_label == 'positive'
        suggestions = [
          "Thank you so much for your kind message! We really appreciate it! ❤️",
          "Your message made our day! Thank you for the positive feedback! 🙌",
          "We're so happy to hear from you! Thanks for the love! ✨"
        ]
      else
        suggestions = [
          "Thanks for your message! We appreciate you reaching out to us.",
          "We received your message and will get back to you soon!",
          "Thank you for contacting us! Our team will respond shortly."
        ]
      end

      suggestions.first(3)
    end

    def self.conversation_history(account, sender_id, limit = 50)
      where(social_media_account: account)
        .where(sender_id: sender_id)
        .order(received_at: :asc)
        .limit(limit)
    end

    def self.response_time_analytics(account, period = 30.days)
      messages = where(social_media_account: account)
                  .where('received_at > ?', period.ago)
                  .where(responded: true)
                  .where.not(responded_at: nil)

      return {} if messages.empty?

      response_times = messages.map do |message|
        (message.responded_at - message.received_at) / 1.hour
      end

      {
        total_messages: messages.count,
        average_response_time: response_times.sum / response_times.length,
        median_response_time: response_times.sort[response_times.length / 2],
        fastest_response: response_times.min,
        slowest_response: response_times.max,
        response_rate: calculate_response_rate(account, period)
      }
    end

    def self.message_volume_trends(account, days = 30)
      end_date = Date.current
      start_date = end_date - days.days

      daily_data = {}
      (start_date..end_date).each { |date| daily_data[date] = 0 }

      messages = where(social_media_account: account)
                  .where(received_at: start_date.beginning_of_day..end_date.end_of_day)
                  .group('DATE(received_at)')
                  .count

      messages.each do |date_string, count|
        date = Date.parse(date_string)
        daily_data[date] = count
      end

      daily_data.map { |date, count| { date: date, count: count } }
    end

    def self.popular_inquiry_topics(account, limit = 20)
      messages = where(social_media_account: account)
                  .where('received_at > ?', 30.days.ago)
                  .where.not(message_text: nil)

      word_frequency = {}

      messages.find_each do |message|
        next unless message.contains_question?

        words = message.message_text.downcase.gsub(/[^\w\s]/, '').split
        words.each do |word|
          next if word.length < 4 || common_words.include?(word)
          word_frequency[word] = (word_frequency[word] || 0) + 1
        end
      end

      word_frequency.sort_by { |word, count| -count }.first(limit).to_h
    end

    private

    def analyze_message_content
      return unless message_text.present?

      # Simple sentiment analysis
      positive_words = %w[love amazing great awesome fantastic wonderful excellent perfect beautiful happy thanks]
      negative_words = %w[hate terrible awful bad worst disappointed angry upset problem issue horrible]

      words = message_text.downcase.split(/\W+/)

      positive_count = words.count { |word| positive_words.include?(word) }
      negative_count = words.count { |word| negative_words.include?(word) }

      total_sentiment_words = positive_count + negative_count

      if total_sentiment_words > 0
        self.sentiment_score = positive_count.to_f / total_sentiment_words
      else
        self.sentiment_score = 0.5 # Neutral
      end
    end

    def determine_priority
      priority = 'low'

      # High priority conditions
      if contains_complaint?
        priority = 'high'
      elsif contains_question? && sentiment_score < 0.4
        priority = 'high'
      elsif message_type == 'story_reply' && sentiment_score < 0.3
        priority = 'high'
      elsif contains_question?
        priority = 'medium'
      elsif sentiment_score > 0.7
        priority = 'medium'
      end

      self.priority_level = priority
    end

    def self.calculate_response_rate(account, period)
      total_messages = where(social_media_account: account)
                        .where('received_at > ?', period.ago)
                        .where.not(message_type: 'automated_message')
                        .count

      return 0 if total_messages.zero?

      responded_messages = where(social_media_account: account)
                            .where('received_at > ?', period.ago)
                            .where.not(message_type: 'automated_message')
                            .where(responded: true)
                            .count

      (responded_messages.to_f / total_messages * 100).round(1)
    end

    def self.common_words
      %w[
        the and or but with for this that have has had will would could should
        can may might must shall about above across after against along among
        around because before behind below beneath beside between beyond during
        except from into like near over since through throughout till until
        upon within without
      ]
    end
  end
end