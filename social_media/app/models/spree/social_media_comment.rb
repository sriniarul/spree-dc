module Spree
  class SocialMediaComment < Spree::Base
    belongs_to :social_media_account, class_name: 'Spree::SocialMediaAccount'
    belongs_to :social_media_post, class_name: 'Spree::SocialMediaPost', optional: true
    belongs_to :parent_comment, class_name: 'Spree::SocialMediaComment', optional: true
    has_many :reply_comments, class_name: 'Spree::SocialMediaComment', foreign_key: 'parent_comment_id', dependent: :destroy

    validates :platform_comment_id, presence: true, uniqueness: { scope: :social_media_account_id }
    validates :text, presence: true
    validates :commenter_id, presence: true

    scope :recent, -> { order(commented_at: :desc) }
    scope :top_level, -> { where(parent_comment_id: nil) }
    scope :replies, -> { where.not(parent_comment_id: nil) }
    scope :unprocessed, -> { where(processed: false) }
    scope :for_post, ->(post) { where(social_media_post: post) }

    before_save :analyze_sentiment
    before_save :detect_language
    before_save :extract_mentions_and_hashtags

    def reply?
      parent_comment_id.present?
    end

    def top_level?
      parent_comment_id.nil?
    end

    def has_replies?
      reply_comments.any?
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

    def requires_attention?
      sentiment_label == 'negative' || contains_flagged_keywords?
    end

    def contains_flagged_keywords?
      return false unless text.present?

      flagged_keywords = [
        'complaint', 'problem', 'issue', 'bad', 'terrible',
        'worst', 'hate', 'awful', 'disappointed', 'refund'
      ]

      flagged_keywords.any? { |keyword| text.downcase.include?(keyword) }
    end

    def extract_metadata
      return {} unless metadata.present?

      JSON.parse(metadata)
    rescue JSON::ParserError
      {}
    end

    def mark_as_processed!
      update!(processed: true, processed_at: Time.current)
    end

    def generate_auto_reply_suggestions
      suggestions = []

      case sentiment_label
      when 'positive'
        suggestions = [
          "Thank you so much for your kind words! ❤️",
          "We're thrilled you love it! Thank you for the support! 🙌",
          "Your feedback means the world to us! Thank you! ✨"
        ]
      when 'negative'
        suggestions = [
          "We're sorry to hear about your experience. Please DM us so we can help resolve this.",
          "Thank you for bringing this to our attention. We'd love to make this right - please send us a message.",
          "We apologize for any inconvenience. Our team would like to help - please reach out via DM."
        ]
      when 'neutral'
        suggestions = [
          "Thanks for taking the time to comment! 🙏",
          "We appreciate your feedback!",
          "Thank you for engaging with our content!"
        ]
      end

      # Add question-specific responses
      if text.include?('?')
        suggestions << "Great question! Let us get back to you with more details."
        suggestions << "Thanks for asking! We'll send you more information via DM."
      end

      suggestions.uniq.first(3)
    end

    def self.sentiment_summary(account, period = 30.days)
      comments = where(social_media_account: account)
                  .where('commented_at > ?', period.ago)

      total_comments = comments.count
      return {} if total_comments.zero?

      positive_count = comments.where('sentiment_score >= ?', 0.6).count
      neutral_count = comments.where(sentiment_score: 0.4...0.6).count
      negative_count = comments.where('sentiment_score < ?', 0.4).count

      {
        total_comments: total_comments,
        positive_count: positive_count,
        neutral_count: neutral_count,
        negative_count: negative_count,
        positive_percentage: (positive_count.to_f / total_comments * 100).round(1),
        neutral_percentage: (neutral_count.to_f / total_comments * 100).round(1),
        negative_percentage: (negative_count.to_f / total_comments * 100).round(1),
        average_sentiment: comments.average(:sentiment_score)&.round(2) || 0
      }
    end

    def self.trending_topics(account, limit = 10)
      # Extract common themes from comments
      comments = where(social_media_account: account)
                  .where('commented_at > ?', 7.days.ago)
                  .pluck(:text)

      word_frequency = {}

      comments.each do |comment|
        words = comment.downcase.gsub(/[^\w\s]/, '').split
        words.each do |word|
          next if word.length < 3 || common_words.include?(word)
          word_frequency[word] = (word_frequency[word] || 0) + 1
        end
      end

      word_frequency.sort_by { |word, count| -count }.first(limit).to_h
    end

    private

    def analyze_sentiment
      return unless text.present?

      # Simple sentiment analysis based on keywords
      # In production, this would use a proper NLP service
      positive_words = %w[love amazing great awesome fantastic wonderful excellent perfect beautiful happy]
      negative_words = %w[hate terrible awful bad worst disappointed angry upset problem issue]

      words = text.downcase.split

      positive_count = words.count { |word| positive_words.include?(word) }
      negative_count = words.count { |word| negative_words.include?(word) }

      total_sentiment_words = positive_count + negative_count

      if total_sentiment_words > 0
        self.sentiment_score = positive_count.to_f / total_sentiment_words
      else
        self.sentiment_score = 0.5 # Neutral
      end
    end

    def detect_language
      return unless text.present?

      # Simple language detection based on common words
      # In production, this would use a proper language detection service
      english_indicators = %w[the and or but with for this that]
      spanish_indicators = %w[el la de que en un una]
      french_indicators = %w[le la de et est dans]

      words = text.downcase.split

      english_count = words.count { |word| english_indicators.include?(word) }
      spanish_count = words.count { |word| spanish_indicators.include?(word) }
      french_count = words.count { |word| french_indicators.include?(word) }

      max_count = [english_count, spanish_count, french_count].max

      self.detected_language = case max_count
                              when english_count then 'en'
                              when spanish_count then 'es'
                              when french_count then 'fr'
                              else 'unknown'
                              end
    end

    def extract_mentions_and_hashtags
      return unless text.present?

      mentions = text.scan(/@\w+/)
      hashtags = text.scan(/#\w+/)

      metadata_hash = extract_metadata
      metadata_hash['mentions'] = mentions
      metadata_hash['hashtags'] = hashtags

      self.metadata = metadata_hash.to_json
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