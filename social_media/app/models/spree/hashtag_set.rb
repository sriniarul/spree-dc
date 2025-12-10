module Spree
  class HashtagSet < Spree::Base
    belongs_to :vendor, class_name: 'Spree::Vendor'
    belongs_to :social_media_account, class_name: 'Spree::SocialMediaAccount', optional: true

    validates :name, presence: true, uniqueness: { scope: [:vendor_id, :social_media_account_id] }
    validates :hashtags, presence: true
    validates :vendor, presence: true

    before_save :normalize_hashtags
    before_save :update_hashtag_count

    scope :for_account, ->(account) { where(social_media_account: [account, nil]) }
    scope :global, -> { where(social_media_account: nil) }
    scope :account_specific, ->(account) { where(social_media_account: account) }
    scope :recently_used, -> { where.not(last_used_at: nil).order(last_used_at: :desc) }
    scope :by_usage, -> { order(usage_count: :desc) }

    def hashtag_array
      return [] if hashtags.blank?
      hashtags.split(/\s+/).map(&:strip).reject(&:blank?)
    end

    def hashtag_array=(tags)
      self.hashtags = Array(tags).join(' ')
    end

    def formatted_hashtags
      hashtag_array.map { |tag| tag.start_with?('#') ? tag : "##{tag}" }
    end

    def hashtag_count
      hashtag_array.length
    end

    def mark_as_used!
      update!(
        last_used_at: Time.current,
        usage_count: (usage_count || 0) + 1
      )
    end

    def similar_sets
      return self.class.none if hashtags.blank?

      # Find sets with overlapping hashtags
      self.class.where(vendor: vendor)
               .where.not(id: id)
               .select { |set| has_overlap_with?(set) }
    end

    def overlap_percentage(other_set)
      return 0 if hashtags.blank? || other_set.hashtags.blank?

      my_hashtags = hashtag_array.map(&:downcase)
      other_hashtags = other_set.hashtag_array.map(&:downcase)

      common = (my_hashtags & other_hashtags).length
      total_unique = (my_hashtags | other_hashtags).length

      return 0 if total_unique == 0
      (common.to_f / total_unique * 100).round(1)
    end

    def performance_metrics
      return {} unless social_media_account

      # Get performance data for posts that used these hashtags
      posts_with_these_hashtags = find_posts_using_hashtags
      return {} if posts_with_these_hashtags.empty?

      analytics = posts_with_these_hashtags
                    .joins(:social_media_analytics)
                    .includes(:social_media_analytics)

      return {} if analytics.empty?

      total_posts = analytics.count
      total_reach = analytics.sum { |p| p.social_media_analytics.first&.reach || 0 }
      total_engagement = analytics.sum { |p| p.social_media_analytics.first&.engagement || 0 }

      {
        posts_count: total_posts,
        avg_reach: total_posts > 0 ? (total_reach.to_f / total_posts).round : 0,
        avg_engagement: total_posts > 0 ? (total_engagement.to_f / total_posts).round : 0,
        total_reach: total_reach,
        total_engagement: total_engagement,
        engagement_rate: total_reach > 0 ? (total_engagement.to_f / total_reach * 100).round(2) : 0
      }
    end

    def effectiveness_score
      metrics = performance_metrics
      return 0 if metrics.empty?

      # Calculate effectiveness based on engagement rate and usage
      engagement_score = [metrics[:engagement_rate] || 0, 10].min * 5  # Max 50 points
      usage_score = [usage_count || 0, 10].min * 3                     # Max 30 points
      reach_score = metrics[:avg_reach] > 1000 ? 20 : 0                # 20 points for good reach

      engagement_score + usage_score + reach_score
    end

    def category_analysis
      categories = {}

      hashtag_array.each do |hashtag|
        category = determine_hashtag_category(hashtag)
        categories[category] ||= 0
        categories[category] += 1
      end

      categories
    end

    def suggested_additions(limit = 5)
      return [] unless social_media_account

      # Analyze high-performing hashtags from the account that aren't in this set
      account_hashtag_performance = social_media_account.analyze_hashtag_performance
      current_hashtags = hashtag_array.map(&:downcase)

      suggestions = account_hashtag_performance.select do |hashtag_data|
        !current_hashtags.include?(hashtag_data[:name].downcase) &&
        hashtag_data[:performance_score] > 50
      end

      suggestions.sort_by { |h| -h[:performance_score] }.first(limit)
    end

    def duplicate_detection
      normalized_hashtags = hashtag_array.map { |tag| tag.gsub('#', '').downcase }
      duplicates = normalized_hashtags.select { |tag| normalized_hashtags.count(tag) > 1 }

      duplicates.uniq
    end

    def validation_report
      report = {
        valid_hashtags: [],
        invalid_hashtags: [],
        warnings: [],
        recommendations: []
      }

      hashtag_array.each do |hashtag|
        if valid_hashtag?(hashtag)
          report[:valid_hashtags] << hashtag
        else
          report[:invalid_hashtags] << hashtag
          report[:warnings] << "Invalid hashtag: #{hashtag}"
        end
      end

      # Check for issues
      duplicates = duplicate_detection
      if duplicates.any?
        report[:warnings] << "Duplicate hashtags found: #{duplicates.join(', ')}"
      end

      if hashtag_count > 30
        report[:warnings] << 'Too many hashtags - Instagram recommends 5-10 per post'
      end

      if hashtag_count < 3
        report[:recommendations] << 'Consider adding more hashtags for better reach'
      end

      # Check for banned hashtags
      potentially_banned = hashtag_array.select { |tag| potentially_banned_hashtag?(tag) }
      if potentially_banned.any?
        report[:warnings] << "Potentially banned hashtags: #{potentially_banned.join(', ')}"
      end

      report
    end

    private

    def normalize_hashtags
      return if hashtags.blank?

      # Normalize hashtags: remove extra spaces, ensure # prefix, remove duplicates
      normalized = hashtags.split(/\s+/)
                          .map(&:strip)
                          .reject(&:blank?)
                          .map { |tag| tag.start_with?('#') ? tag : "##{tag}" }
                          .map(&:downcase)
                          .uniq

      self.hashtags = normalized.join(' ')
    end

    def update_hashtag_count
      self.hashtag_count_cache = hashtag_array.length
    end

    def has_overlap_with?(other_set)
      return false if hashtags.blank? || other_set.hashtags.blank?

      my_hashtags = hashtag_array.map(&:downcase)
      other_hashtags = other_set.hashtag_array.map(&:downcase)

      (my_hashtags & other_hashtags).any?
    end

    def find_posts_using_hashtags
      return [] unless social_media_account

      my_hashtags = hashtag_array.map(&:downcase)

      social_media_account.social_media_posts.published.select do |post|
        post_hashtags = extract_post_hashtags(post).map(&:downcase)
        (my_hashtags & post_hashtags).length >= (my_hashtags.length * 0.5).ceil # At least 50% match
      end
    end

    def extract_post_hashtags(post)
      hashtags = []

      # Extract from caption
      if post.caption.present?
        hashtags.concat(post.caption.scan(/#\w+/))
      end

      # Extract from hashtags field
      if post.hashtags.present?
        field_hashtags = post.hashtags.split(/[\s,]+/).map do |tag|
          tag.start_with?('#') ? tag : "##{tag}"
        end
        hashtags.concat(field_hashtags)
      end

      hashtags.uniq
    end

    def determine_hashtag_category(hashtag)
      tag = hashtag.downcase.gsub('#', '')

      return 'brand' if tag.include?(vendor.name.downcase.gsub(/[^a-z0-9]/, ''))
      return 'location' if location_hashtag?(tag)
      return 'trending' if trending_hashtag?(tag)
      return 'niche' if niche_hashtag?(tag)

      'general'
    end

    def location_hashtag?(tag)
      location_keywords = %w[city town local community neighborhood area region country]
      location_keywords.any? { |keyword| tag.include?(keyword) }
    end

    def trending_hashtag?(tag)
      trending_keywords = %w[trending viral explore fyp popular hot new]
      trending_keywords.any? { |keyword| tag.include?(keyword) }
    end

    def niche_hashtag?(tag)
      # This would be more sophisticated in a real implementation
      # Check against industry-specific keywords based on vendor category
      business_category = vendor.business_category&.downcase || ''

      case business_category
      when 'fashion', 'clothing'
        %w[fashion style outfit ootd clothing apparel].any? { |keyword| tag.include?(keyword) }
      when 'food', 'restaurant'
        %w[food recipe cooking chef restaurant foodie].any? { |keyword| tag.include?(keyword) }
      when 'fitness', 'health'
        %w[fitness workout health wellness gym exercise].any? { |keyword| tag.include?(keyword) }
      else
        false
      end
    end

    def valid_hashtag?(hashtag)
      return false if hashtag.blank?
      return false unless hashtag.start_with?('#')
      return false if hashtag.length > 100
      return false if hashtag.match?(/[^#\w]/) # Only allow word characters and #
      return false if hashtag.length < 2  # Must have at least one character after #

      true
    end

    def potentially_banned_hashtag?(hashtag)
      banned_patterns = [
        /follow.*follow/i,
        /like.*like/i,
        /spam/i,
        /bot/i,
        /fake/i,
        /buy.*follow/i,
        /get.*follow/i
      ]

      banned_patterns.any? { |pattern| hashtag.match?(pattern) }
    end
  end
end