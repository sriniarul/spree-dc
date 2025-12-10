module Spree
  class SocialMediaTemplate < Spree::Base
    belongs_to :vendor, class_name: 'Spree::Vendor'
    belongs_to :social_media_account, class_name: 'Spree::SocialMediaAccount', optional: true
    has_many :social_media_posts, class_name: 'Spree::SocialMediaPost', foreign_key: 'template_id', dependent: :nullify
    has_many_attached :template_media

    validates :name, presence: true, length: { maximum: 255 }
    validates :template_type, presence: true, inclusion: { in: %w[post story reel carousel] }
    validates :content_category, presence: true
    validates :vendor, presence: true

    before_save :extract_template_variables
    before_save :generate_preview_text

    # Template types
    TEMPLATE_TYPES = {
      'post' => 'Regular Post',
      'story' => 'Instagram Story',
      'reel' => 'Instagram Reel',
      'carousel' => 'Carousel Post'
    }.freeze

    # Content categories for templates
    CONTENT_CATEGORIES = [
      'product_showcase',
      'promotional',
      'educational',
      'behind_the_scenes',
      'user_generated_content',
      'seasonal_holiday',
      'announcement',
      'testimonial_review',
      'how_to_tutorial',
      'brand_story',
      'event_coverage',
      'quote_inspiration',
      'industry_news',
      'community_engagement',
      'other'
    ].freeze

    # Scopes
    scope :active, -> { where(active: true) }
    scope :by_type, ->(type) { where(template_type: type) }
    scope :by_category, ->(category) { where(content_category: category) }
    scope :for_account, ->(account) { where(social_media_account: [account, nil]) }
    scope :global, -> { where(social_media_account: nil) }
    scope :recently_used, -> { order(last_used_at: :desc) }
    scope :popular, -> { where('usage_count > ?', 5) }

    # Template variable patterns
    VARIABLE_PATTERN = /\{\{([^}]+)\}\}/.freeze

    def template_type_display
      TEMPLATE_TYPES[template_type] || template_type.humanize
    end

    def content_category_display
      content_category.humanize.titleize
    end

    def template_variables
      variables = []

      # Extract from caption
      if caption_template.present?
        caption_matches = caption_template.scan(VARIABLE_PATTERN)
        variables.concat(caption_matches.flatten)
      end

      # Extract from hashtags
      if hashtags_template.present?
        hashtag_matches = hashtags_template.scan(VARIABLE_PATTERN)
        variables.concat(hashtag_matches.flatten)
      end

      variables.uniq.sort
    end

    def render_template(variables = {})
      rendered_caption = render_template_string(caption_template, variables)
      rendered_hashtags = render_template_string(hashtags_template, variables)

      {
        caption: rendered_caption,
        hashtags: rendered_hashtags,
        media_requirements: media_requirements_data,
        posting_instructions: instructions,
        variables_used: variables.keys
      }
    end

    def preview_with_sample_data
      sample_variables = generate_sample_variables
      render_template(sample_variables)
    end

    def usage_analytics
      return {} unless social_media_posts.any?

      posts = social_media_posts.published.includes(:social_media_analytics)
      analytics = posts.joins(:social_media_analytics)

      return {} if analytics.empty?

      total_posts = posts.count
      total_reach = analytics.sum { |p| p.social_media_analytics.first&.reach || 0 }
      total_engagement = analytics.sum { |p| p.social_media_analytics.first&.engagement || 0 }

      {
        posts_created: total_posts,
        total_reach: total_reach,
        total_engagement: total_engagement,
        avg_reach: total_posts > 0 ? (total_reach.to_f / total_posts).round : 0,
        avg_engagement: total_posts > 0 ? (total_engagement.to_f / total_posts).round : 0,
        avg_engagement_rate: total_reach > 0 ? (total_engagement.to_f / total_reach * 100).round(2) : 0,
        performance_score: calculate_performance_score(total_reach, total_engagement, total_posts)
      }
    end

    def mark_as_used!
      increment!(:usage_count)
      touch(:last_used_at)
    end

    def duplicate_for_vendor(target_vendor)
      new_template = self.dup
      new_template.vendor = target_vendor
      new_template.name = "#{name} (Copy)"
      new_template.usage_count = 0
      new_template.last_used_at = nil

      # Copy attached media if any
      if template_media.attached?
        template_media.each do |media|
          new_template.template_media.attach(
            io: media.blob.download,
            filename: media.filename,
            content_type: media.content_type
          )
        end
      end

      new_template.save
      new_template
    end

    def media_requirements_met?(attached_media)
      return true unless media_requirements_data.present?

      requirements = JSON.parse(media_requirements_data)
      return true unless requirements.is_a?(Hash)

      # Check minimum media count
      min_count = requirements['min_count'] || 0
      return false if attached_media.count < min_count

      # Check maximum media count
      max_count = requirements['max_count']
      return false if max_count && attached_media.count > max_count

      # Check media types
      if requirements['allowed_types'].present?
        allowed_types = requirements['allowed_types']
        attached_media.each do |media|
          content_type = media.content_type || media.blob.content_type
          media_type = content_type.split('/').first

          return false unless allowed_types.include?(media_type)
        end
      end

      # Check aspect ratios for images
      if requirements['aspect_ratios'].present? && template_type == 'post'
        required_ratios = requirements['aspect_ratios']

        attached_media.each do |media|
          next unless media.image?

          begin
            metadata = media.metadata || {}
            width = metadata['width']
            height = metadata['height']

            if width && height
              ratio = (width.to_f / height).round(2)
              closest_ratio = required_ratios.min_by { |r| (r - ratio).abs }
              return false if (closest_ratio - ratio).abs > 0.1
            end
          rescue
            # Skip validation if metadata not available
          end
        end
      end

      true
    end

    def suggested_improvements
      suggestions = []

      # Analyze caption length
      if caption_template.present?
        caption_length = caption_template.length
        if caption_length < 50
          suggestions << "Consider adding more detail to your caption for better engagement"
        elsif caption_length > 2200
          suggestions << "Caption might be too long - Instagram has a 2,200 character limit"
        end
      end

      # Analyze hashtags
      if hashtags_template.present?
        hashtag_count = hashtags_template.scan(/#\w+/).length
        if hashtag_count < 5
          suggestions << "Add more hashtags to improve discoverability (5-30 recommended)"
        elsif hashtag_count > 30
          suggestions << "Too many hashtags might look spammy - consider reducing to 20-30"
        end
      end

      # Analyze call-to-action presence
      if caption_template.present?
        cta_keywords = ['click', 'visit', 'shop', 'buy', 'learn more', 'swipe', 'comment', 'share', 'follow', 'tag']
        has_cta = cta_keywords.any? { |keyword| caption_template.downcase.include?(keyword) }
        unless has_cta
          suggestions << "Consider adding a clear call-to-action to drive engagement"
        end
      end

      # Template usage analysis
      if usage_count == 0
        suggestions << "This template hasn't been used yet - test it with a post to gather performance data"
      elsif usage_count > 10
        analytics = usage_analytics
        if analytics[:avg_engagement_rate] && analytics[:avg_engagement_rate] < 2
          suggestions << "This template's engagement rate is below average - consider updating the content"
        end
      end

      suggestions
    end

    def self.create_from_post(post)
      template = new(
        vendor: post.vendor,
        social_media_account: post.social_media_account,
        name: "Template from #{post.created_at.strftime('%m/%d/%Y')}",
        template_type: post.content_type || 'post',
        caption_template: templatize_text(post.caption),
        hashtags_template: post.hashtags,
        content_category: 'other',
        instructions: "Generated from successful post (ID: #{post.id})"
      )

      # Copy media if available
      if post.media_attachments.attached?
        post.media_attachments.each do |media|
          template.template_media.attach(media.blob)
        end
      end

      template.save
      template
    end

    def self.popular_templates(limit = 10)
      active.joins(:social_media_posts)
            .group('spree_social_media_templates.id')
            .order('AVG(spree_social_media_analytics.engagement_rate) DESC NULLS LAST')
            .limit(limit)
    end

    def self.content_category_options
      CONTENT_CATEGORIES.map { |category| [category.humanize.titleize, category] }
    end

    private

    def extract_template_variables
      self.template_variables_data = template_variables.to_json
    end

    def generate_preview_text
      if caption_template.present?
        preview = render_template_string(caption_template, generate_sample_variables)
        self.preview_text = preview.truncate(200)
      end
    end

    def render_template_string(template_string, variables)
      return template_string unless template_string.present?

      rendered = template_string.dup
      variables.each do |key, value|
        placeholder = "{{#{key}}}"
        rendered.gsub!(placeholder, value.to_s)
      end

      # Handle any remaining unmatched variables
      rendered.gsub!(VARIABLE_PATTERN) do |match|
        variable_name = match.gsub(/[{}]/, '')
        "[#{variable_name.humanize}]"
      end

      rendered
    end

    def generate_sample_variables
      sample_data = {
        'product_name' => 'Amazing Product',
        'brand_name' => vendor.display_name,
        'price' => '$99.99',
        'discount' => '20%',
        'date' => Date.current.strftime('%B %d'),
        'season' => current_season,
        'location' => 'Your City',
        'customer_name' => 'Sarah',
        'website' => vendor.website_url || 'yourwebsite.com'
      }

      # Add any custom variables from the template
      template_variables.each do |var|
        next if sample_data.key?(var)

        sample_data[var] = case var.downcase
                          when /name/ then 'John Doe'
                          when /price|cost|amount/ then '$49.99'
                          when /percent|discount/ then '15%'
                          when /date/ then Date.current.strftime('%m/%d/%Y')
                          when /time/ then Time.current.strftime('%I:%M %p')
                          when /color/ then 'Blue'
                          when /size/ then 'Medium'
                          else "[#{var.humanize}]"
                          end
      end

      sample_data
    end

    def current_season
      month = Date.current.month
      case month
      when 12, 1, 2 then 'Winter'
      when 3, 4, 5 then 'Spring'
      when 6, 7, 8 then 'Summer'
      when 9, 10, 11 then 'Fall'
      end
    end

    def calculate_performance_score(total_reach, total_engagement, total_posts)
      return 0 if total_posts == 0

      avg_reach = total_reach.to_f / total_posts
      avg_engagement = total_engagement.to_f / total_posts
      engagement_rate = total_reach > 0 ? (total_engagement.to_f / total_reach * 100) : 0

      # Score based on engagement rate (0-100)
      engagement_score = [engagement_rate * 10, 100].min

      # Bonus for reach
      reach_score = case avg_reach
                   when 0..999 then 0
                   when 1000..4999 then 10
                   when 5000..9999 then 20
                   when 10000..49999 then 30
                   else 40
                   end

      # Usage bonus (templates that are used more get higher scores)
      usage_score = [usage_count * 2, 20].min

      (engagement_score + reach_score + usage_score).round
    end

    def self.templatize_text(text)
      return text unless text.present?

      # Replace common patterns with template variables
      templatized = text.dup

      # Replace product names (if they exist in the text)
      # This would be more sophisticated in a real implementation
      templatized.gsub!(/\b[A-Z][a-z]+ [A-Z][a-z]+\b/, '{{product_name}}') # Simple product name pattern

      # Replace prices
      templatized.gsub!(/\$[\d,]+\.?\d*/, '{{price}}')

      # Replace percentages (likely discounts)
      templatized.gsub!(/\d+%\s*off/i, '{{discount}} off')

      # Replace dates
      templatized.gsub!(/\b(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2}(?:st|nd|rd|th)?\b/, '{{date}}')

      templatized
    end
  end
end