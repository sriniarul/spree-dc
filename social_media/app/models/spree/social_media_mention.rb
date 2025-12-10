module Spree
  class SocialMediaMention < Spree::Base
    belongs_to :social_media_account, class_name: 'Spree::SocialMediaAccount'

    validates :platform_mention_id, presence: true, uniqueness: { scope: :social_media_account_id }
    validates :from_username, presence: true
    validates :mention_type, presence: true

    scope :recent, -> { order(occurred_at: :desc) }
    scope :unprocessed, -> { where(processed: false) }
    scope :by_type, ->(type) { where(mention_type: type) }
    scope :requiring_attention, -> { where(requires_attention: true) }

    # Mention types
    MENTION_TYPES = %w[post_mention comment_mention story_mention direct_mention].freeze

    validates :mention_type, inclusion: { in: MENTION_TYPES }

    before_save :analyze_mention_context
    before_save :determine_priority_level

    def metadata_hash
      return {} unless metadata.present?

      JSON.parse(metadata)
    rescue JSON::ParserError
      {}
    end

    def mark_as_processed!
      update!(processed: true, processed_at: Time.current)
    end

    def high_priority?
      priority_level == 'high'
    end

    def requires_response?
      mention_context == 'question' || mention_context == 'complaint' || high_priority?
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

    def generate_response_suggestions
      suggestions = []

      case mention_context
      when 'compliment'
        suggestions = [
          "Thank you so much! We really appreciate your kind words! ❤️",
          "This made our day! Thank you for the love! 🙏",
          "We're thrilled you think so! Thanks for the support! ✨"
        ]
      when 'question'
        suggestions = [
          "Great question! We'll send you more details via DM.",
          "Thanks for asking! Let us get back to you with that information.",
          "We'd be happy to help! Please check your DMs for more info."
        ]
      when 'complaint'
        suggestions = [
          "We're sorry to hear about your experience. We'd love to make this right - please DM us.",
          "Thank you for bringing this to our attention. Our team will reach out to help resolve this.",
          "We apologize for any inconvenience. Please send us a message so we can assist you."
        ]
      when 'tag_friend'
        suggestions = [
          "Thanks for sharing us with your friend! 🙌",
          "Love when our community shares the love! Thank you!",
          "Thanks for spreading the word! We appreciate it!"
        ]
      when 'repost_request'
        suggestions = [
          "We'd love to share this! Thanks for tagging us!",
          "Thank you for thinking of us! We'll check this out!",
          "Awesome content! Thanks for the tag!"
        ]
      else
        suggestions = [
          "Thanks for the mention! 🙏",
          "We appreciate you thinking of us!",
          "Thank you for the tag!"
        ]
      end

      suggestions.uniq.first(3)
    end

    def self.mentions_summary(account, period = 30.days)
      mentions = where(social_media_account: account)
                  .where('occurred_at > ?', period.ago)

      total_mentions = mentions.count
      return {} if total_mentions.zero?

      {
        total_mentions: total_mentions,
        unprocessed_mentions: mentions.unprocessed.count,
        high_priority_mentions: mentions.where(priority_level: 'high').count,
        mention_types: mentions.group(:mention_type).count,
        mention_contexts: mentions.group(:mention_context).count,
        sentiment_breakdown: {
          positive: mentions.where('sentiment_score >= ?', 0.6).count,
          neutral: mentions.where(sentiment_score: 0.4...0.6).count,
          negative: mentions.where('sentiment_score < ?', 0.4).count
        },
        response_rate: calculate_response_rate(mentions),
        average_response_time: calculate_average_response_time(mentions)
      }
    end

    def self.trending_mention_sources(account, period = 7.days, limit = 10)
      # Find users who mention the account most frequently
      mentions = where(social_media_account: account)
                  .where('occurred_at > ?', period.ago)

      mention_frequency = mentions.group(:from_username).count
                                 .sort_by { |username, count| -count }
                                 .first(limit)

      mention_frequency.map do |username, count|
        user_mentions = mentions.where(from_username: username)
        avg_sentiment = user_mentions.average(:sentiment_score) || 0

        {
          username: username,
          mention_count: count,
          avg_sentiment: avg_sentiment.round(2),
          sentiment_label: sentiment_label_for_score(avg_sentiment),
          last_mention: user_mentions.maximum(:occurred_at),
          mention_types: user_mentions.group(:mention_type).count
        }
      end
    end

    def self.mention_response_opportunities(account, limit = 20)
      # Find mentions that haven't been responded to and should be prioritized
      unresponded_mentions = where(social_media_account: account)
                              .where(responded: false)
                              .where('occurred_at > ?', 7.days.ago)
                              .order(:priority_level, :occurred_at)

      opportunities = []

      unresponded_mentions.limit(limit).each do |mention|
        opportunity_score = calculate_opportunity_score(mention)

        opportunities << {
          mention: mention,
          opportunity_score: opportunity_score,
          suggested_response: mention.generate_response_suggestions.first,
          urgency: mention.high_priority? ? 'high' : 'medium',
          context: mention.mention_context,
          sentiment: mention.sentiment_label
        }
      end

      opportunities.sort_by { |opp| -opp[:opportunity_score] }
    end

    def self.mention_analytics_by_content(account, period = 30.days)
      # Analyze which types of content generate the most mentions
      mentions = joins("LEFT JOIN spree_social_media_posts ON spree_social_media_mentions.media_id = spree_social_media_posts.platform_post_id")
                  .where(social_media_account: account)
                  .where('spree_social_media_mentions.occurred_at > ?', period.ago)

      content_mention_data = mentions.group('spree_social_media_posts.content_type')
                                   .select('spree_social_media_posts.content_type,
                                          COUNT(*) as mention_count,
                                          AVG(spree_social_media_mentions.sentiment_score) as avg_sentiment')

      content_mention_data.map do |data|
        {
          content_type: data.content_type || 'unknown',
          mention_count: data.mention_count,
          avg_sentiment: data.avg_sentiment&.round(2) || 0
        }
      end.sort_by { |data| -data[:mention_count] }
    end

    private

    def analyze_mention_context
      return unless from_username.present?

      # Get mention text from metadata
      mention_text = extract_mention_text

      self.mention_context = determine_mention_context(mention_text)
      self.sentiment_score = analyze_mention_sentiment(mention_text)
    end

    def extract_mention_text
      metadata_data = metadata_hash

      # Try to extract text from various possible fields in metadata
      mention_text = metadata_data['text'] ||
                    metadata_data['message'] ||
                    metadata_data['caption'] ||
                    ''

      mention_text.to_s.downcase
    end

    def determine_mention_context(text)
      return 'unknown' if text.blank?

      # Question indicators
      if text.include?('?') || text.match?(/\b(what|how|when|where|why|which|can|could|would|should|is|are|do|does)\b/)
        return 'question'
      end

      # Complaint indicators
      complaint_keywords = %w[problem issue complaint bad terrible awful disappointed refund help support]
      if complaint_keywords.any? { |keyword| text.include?(keyword) }
        return 'complaint'
      end

      # Compliment indicators
      compliment_keywords = %w[love amazing awesome great fantastic wonderful beautiful perfect excellent]
      if compliment_keywords.any? { |keyword| text.include?(keyword) }
        return 'compliment'
      end

      # Tag friend pattern
      if text.match?(/@\w+/) && text.match?(/\b(check|look|see)\b/)
        return 'tag_friend'
      end

      # Repost request
      if text.match?(/\b(repost|share|feature)\b/)
        return 'repost_request'
      end

      'general'
    end

    def analyze_mention_sentiment(text)
      return 0.5 if text.blank?

      positive_words = %w[love amazing great awesome fantastic wonderful excellent perfect beautiful happy good best]
      negative_words = %w[hate terrible awful bad worst disappointed angry upset problem issue horrible]

      words = text.split(/\W+/)

      positive_count = words.count { |word| positive_words.include?(word.downcase) }
      negative_count = words.count { |word| negative_words.include?(word.downcase) }

      total_sentiment_words = positive_count + negative_count

      if total_sentiment_words > 0
        positive_count.to_f / total_sentiment_words
      else
        0.5 # Neutral
      end
    end

    def determine_priority_level
      priority = 'low'

      # High priority conditions
      if mention_context == 'complaint'
        priority = 'high'
      elsif mention_context == 'question' && sentiment_score < 0.4
        priority = 'high'
      elsif follower_count_high? # If from a user with many followers
        priority = 'medium'
      elsif mention_context == 'question'
        priority = 'medium'
      elsif sentiment_score > 0.7
        priority = 'medium'
      end

      self.priority_level = priority
      self.requires_attention = (priority == 'high')
    end

    def follower_count_high?
      # This would check the follower count of the mentioning user
      # For now, we'll use a simple heuristic based on username patterns
      metadata_data = metadata_hash
      follower_count = metadata_data.dig('from', 'follower_count')

      return false unless follower_count

      follower_count > 10000 # Consider users with 10k+ followers as high influence
    end

    def self.calculate_response_rate(mentions)
      total_mentions = mentions.count
      return 0 if total_mentions.zero?

      responded_mentions = mentions.where(responded: true).count
      (responded_mentions.to_f / total_mentions * 100).round(1)
    end

    def self.calculate_average_response_time(mentions)
      responded_mentions = mentions.where(responded: true)
                                 .where.not(responded_at: nil)

      return 0 if responded_mentions.empty?

      total_response_time = responded_mentions.sum do |mention|
        (mention.responded_at - mention.occurred_at) / 1.hour
      end

      (total_response_time / responded_mentions.count).round(1)
    end

    def self.sentiment_label_for_score(score)
      case score
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

    def self.calculate_opportunity_score(mention)
      score = 0

      # Base score by priority
      score += case mention.priority_level
              when 'high' then 50
              when 'medium' then 30
              when 'low' then 10
              else 0
              end

      # Bonus for positive sentiment (engagement opportunity)
      score += 20 if mention.sentiment_score > 0.6

      # Penalty for very old mentions
      days_old = (Time.current - mention.occurred_at) / 1.day
      score -= (days_old * 5).to_i if days_old > 1

      # Context bonuses
      score += case mention.mention_context
              when 'question' then 15
              when 'complaint' then 25
              when 'compliment' then 10
              else 5
              end

      [score, 100].min
    end
  end
end