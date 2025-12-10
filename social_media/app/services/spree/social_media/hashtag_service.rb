module Spree
  module SocialMedia
    class HashtagService
      include HTTParty
      base_uri 'https://graph.facebook.com/v18.0'

      def initialize(social_media_account)
        @account = social_media_account
        @access_token = @account.access_token
        @instagram_business_account_id = @account.platform_account_id
      end

      def search_hashtags(query, limit = 50)
        return { hashtags: [], error: 'Query is required' } if query.blank?

        begin
          response = HTTParty.get("#{self.class.base_uri}/ig_hashtag_search", {
            query: {
              user_id: @instagram_business_account_id,
              q: query,
              access_token: @access_token,
              limit: limit
            }
          })

          if response.success?
            hashtags = response['data'].map do |hashtag_data|
              {
                id: hashtag_data['id'],
                name: hashtag_data['name'],
                media_count: get_hashtag_media_count(hashtag_data['id']),
                difficulty: calculate_hashtag_difficulty(hashtag_data['name']),
                relevance_score: calculate_relevance_score(hashtag_data['name'], query)
              }
            end

            { hashtags: hashtags, success: true }
          else
            { hashtags: [], error: response['error']['message'] }
          end
        rescue => e
          { hashtags: [], error: "Failed to search hashtags: #{e.message}" }
        end
      end

      def get_hashtag_insights(hashtag_id, limit = 25)
        begin
          response = HTTParty.get("#{self.class.base_uri}/#{hashtag_id}", {
            query: {
              fields: 'id,name',
              access_token: @access_token
            }
          })

          if response.success?
            media_response = HTTParty.get("#{self.class.base_uri}/#{hashtag_id}/recent_media", {
              query: {
                user_id: @instagram_business_account_id,
                fields: 'id,media_type,media_url,permalink,timestamp,like_count,comments_count',
                limit: limit,
                access_token: @access_token
              }
            })

            if media_response.success?
              recent_media = media_response['data'] || []
              {
                hashtag_info: response,
                recent_media: recent_media,
                performance_metrics: calculate_hashtag_performance(recent_media),
                success: true
              }
            else
              { error: media_response['error']['message'], success: false }
            end
          else
            { error: response['error']['message'], success: false }
          end
        rescue => e
          { error: "Failed to get hashtag insights: #{e.message}", success: false }
        end
      end

      def suggest_hashtags_for_content(content_description, caption = '', existing_hashtags = [])
        suggestions = {
          trending: get_trending_hashtags_for_niche(content_description),
          niche_specific: get_niche_specific_hashtags(content_description),
          location_based: get_location_hashtags,
          engagement_optimized: get_high_engagement_hashtags,
          brand_specific: get_brand_hashtags
        }

        # Remove hashtags that are already being used
        existing_hashtag_names = existing_hashtags.map(&:downcase)
        suggestions.each do |category, hashtags|
          suggestions[category] = hashtags.reject { |h| existing_hashtag_names.include?(h[:name].downcase) }
        end

        # Score and rank all suggestions
        all_suggestions = []
        suggestions.each do |category, hashtags|
          hashtags.each do |hashtag|
            hashtag[:category] = category
            hashtag[:score] = calculate_hashtag_score(hashtag, content_description, caption)
            all_suggestions << hashtag
          end
        end

        {
          suggestions: suggestions,
          ranked_suggestions: all_suggestions.sort_by { |h| -h[:score] }.first(30),
          recommendation: generate_hashtag_recommendation(all_suggestions, content_description)
        }
      end

      def analyze_account_hashtag_performance(days_back = 30)
        posts = @account.social_media_posts
                       .published
                       .joins(:social_media_analytics)
                       .where('published_at > ?', days_back.days.ago)

        hashtag_performance = {}
        total_posts_analyzed = 0

        posts.each do |post|
          hashtags = extract_hashtags_from_post(post)
          analytics = post.social_media_analytics.first

          next unless analytics && hashtags.any?

          total_posts_analyzed += 1
          engagement_rate = analytics.reach > 0 ? (analytics.engagement.to_f / analytics.reach * 100) : 0

          hashtags.each do |hashtag|
            hashtag_key = hashtag.gsub('#', '').downcase

            hashtag_performance[hashtag_key] ||= {
              name: hashtag,
              usage_count: 0,
              total_reach: 0,
              total_engagement: 0,
              total_impressions: 0,
              posts: []
            }

            hashtag_performance[hashtag_key][:usage_count] += 1
            hashtag_performance[hashtag_key][:total_reach] += analytics.reach || 0
            hashtag_performance[hashtag_key][:total_engagement] += analytics.engagement || 0
            hashtag_performance[hashtag_key][:total_impressions] += analytics.impressions || 0
            hashtag_performance[hashtag_key][:posts] << {
              id: post.id,
              reach: analytics.reach,
              engagement: analytics.engagement,
              engagement_rate: engagement_rate
            }
          end
        end

        # Calculate averages and performance scores
        performance_data = hashtag_performance.map do |hashtag, data|
          avg_reach = data[:usage_count] > 0 ? (data[:total_reach].to_f / data[:usage_count]).round : 0
          avg_engagement = data[:usage_count] > 0 ? (data[:total_engagement].to_f / data[:usage_count]).round : 0
          avg_engagement_rate = data[:posts].map { |p| p[:engagement_rate] }.sum / data[:usage_count]

          {
            name: data[:name],
            usage_count: data[:usage_count],
            avg_reach: avg_reach,
            avg_engagement: avg_engagement,
            avg_engagement_rate: avg_engagement_rate.round(2),
            performance_score: calculate_hashtag_performance_score(avg_engagement_rate, data[:usage_count]),
            consistency: calculate_hashtag_consistency(data[:posts])
          }
        end

        {
          performance_data: performance_data.sort_by { |h| -h[:performance_score] },
          summary: {
            total_hashtags_used: hashtag_performance.size,
            total_posts_analyzed: total_posts_analyzed,
            avg_hashtags_per_post: total_posts_analyzed > 0 ? (hashtag_performance.values.sum { |h| h[:usage_count] }.to_f / total_posts_analyzed).round(1) : 0,
            top_performing_hashtags: performance_data.sort_by { |h| -h[:performance_score] }.first(10)
          }
        }
      end

      def generate_hashtag_strategy(business_category, target_audience, content_goals)
        strategy = {
          recommended_mix: get_recommended_hashtag_mix(business_category),
          content_specific: get_content_specific_strategy(content_goals),
          audience_targeted: get_audience_targeted_hashtags(target_audience),
          timing_recommendations: get_hashtag_timing_recommendations,
          best_practices: get_hashtag_best_practices
        }

        {
          strategy: strategy,
          implementation_plan: generate_implementation_plan(strategy),
          monitoring_recommendations: get_monitoring_recommendations
        }
      end

      private

      def get_hashtag_media_count(hashtag_id)
        begin
          response = HTTParty.get("#{self.class.base_uri}/#{hashtag_id}", {
            query: {
              fields: 'media_count',
              access_token: @access_token
            }
          })

          response.success? ? response['media_count'] : 0
        rescue
          0
        end
      end

      def calculate_hashtag_difficulty(hashtag_name)
        # Simplified difficulty calculation based on character count and common patterns
        case hashtag_name.length
        when 1..10
          'high'  # Short hashtags are very competitive
        when 11..20
          'medium'
        else
          'low'   # Longer hashtags are more niche
        end
      end

      def calculate_relevance_score(hashtag_name, query)
        return 100 if hashtag_name.downcase == query.downcase

        query_words = query.downcase.split
        hashtag_words = hashtag_name.downcase.gsub(/[^a-z0-9]/, ' ').split

        common_words = query_words & hashtag_words
        (common_words.length.to_f / query_words.length * 100).round
      end

      def calculate_hashtag_performance(recent_media)
        return { avg_likes: 0, avg_comments: 0, total_posts: 0 } if recent_media.empty?

        total_likes = recent_media.sum { |media| media['like_count'] || 0 }
        total_comments = recent_media.sum { |media| media['comments_count'] || 0 }

        {
          avg_likes: (total_likes.to_f / recent_media.length).round,
          avg_comments: (total_comments.to_f / recent_media.length).round,
          total_posts: recent_media.length,
          engagement_rate: calculate_media_engagement_rate(recent_media)
        }
      end

      def calculate_media_engagement_rate(media_array)
        return 0 if media_array.empty?

        total_engagement = media_array.sum do |media|
          (media['like_count'] || 0) + (media['comments_count'] || 0)
        end

        # Estimate reach as 10x engagement (industry average approximation)
        estimated_reach = total_engagement * 10
        estimated_reach > 0 ? (total_engagement.to_f / estimated_reach * 100).round(2) : 0
      end

      def get_trending_hashtags_for_niche(content_description)
        # This would typically connect to trending hashtag APIs or databases
        # For now, return some common trending hashtags based on content type
        keywords = content_description.downcase.split

        trending_base = []

        if keywords.any? { |w| ['fashion', 'style', 'outfit'].include?(w) }
          trending_base = ['#fashion', '#style', '#ootd', '#fashionista', '#styleinspo']
        elsif keywords.any? { |w| ['food', 'recipe', 'cooking'].include?(w) }
          trending_base = ['#foodie', '#recipe', '#cooking', '#instafood', '#foodphotography']
        elsif keywords.any? { |w| ['fitness', 'workout', 'gym'].include?(w) }
          trending_base = ['#fitness', '#workout', '#fitnessmotivation', '#gym', '#healthylifestyle']
        else
          trending_base = ['#trending', '#viral', '#explore', '#fyp', '#instagood']
        end

        trending_base.map do |hashtag|
          {
            name: hashtag,
            difficulty: calculate_hashtag_difficulty(hashtag),
            estimated_reach: rand(10000..100000),
            trending_score: rand(70..100)
          }
        end
      end

      def get_niche_specific_hashtags(content_description)
        # Generate niche hashtags based on content description
        keywords = content_description.downcase.split

        niche_hashtags = keywords.map do |keyword|
          variations = [
            "##{keyword}",
            "##{keyword}gram",
            "##{keyword}lover",
            "##{keyword}life",
            "#daily#{keyword}"
          ]

          variations.map do |hashtag|
            {
              name: hashtag,
              difficulty: 'low',
              estimated_reach: rand(1000..10000),
              niche_relevance: 95
            }
          end
        end.flatten

        niche_hashtags.first(10)
      end

      def get_location_hashtags
        # This would integrate with location services
        # For now, return generic location hashtags
        [
          { name: '#localbusiness', difficulty: 'medium', estimated_reach: 50000 },
          { name: '#local', difficulty: 'high', estimated_reach: 100000 },
          { name: '#community', difficulty: 'medium', estimated_reach: 75000 }
        ]
      end

      def get_high_engagement_hashtags
        # These are hashtags known for high engagement
        [
          { name: '#engagement', difficulty: 'high', estimated_reach: 200000, engagement_rate: 4.2 },
          { name: '#interactive', difficulty: 'medium', estimated_reach: 50000, engagement_rate: 3.8 },
          { name: '#community', difficulty: 'medium', estimated_reach: 75000, engagement_rate: 3.5 }
        ]
      end

      def get_brand_hashtags
        # Generate brand-specific hashtags
        vendor_name = @account.vendor&.name&.downcase&.gsub(/[^a-z0-9]/, '')
        return [] unless vendor_name

        [
          { name: "##{vendor_name}", difficulty: 'low', estimated_reach: 1000, brand_specific: true },
          { name: "##{vendor_name}brand", difficulty: 'low', estimated_reach: 500, brand_specific: true }
        ]
      end

      def calculate_hashtag_score(hashtag, content_description, caption)
        score = 0

        # Base score from difficulty (inverse relationship)
        score += case hashtag[:difficulty]
                when 'low' then 30
                when 'medium' then 20
                when 'high' then 10
                else 15
                end

        # Relevance bonus
        score += hashtag[:relevance_score] if hashtag[:relevance_score]
        score += hashtag[:niche_relevance] if hashtag[:niche_relevance]

        # Engagement bonus
        score += (hashtag[:engagement_rate] || 0) * 5

        # Brand bonus
        score += 25 if hashtag[:brand_specific]

        score
      end

      def extract_hashtags_from_post(post)
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

      def calculate_hashtag_performance_score(avg_engagement_rate, usage_count)
        # Higher engagement rate = better score, but also consider usage frequency
        engagement_score = avg_engagement_rate * 10
        frequency_bonus = usage_count > 3 ? 10 : 0  # Bonus for hashtags used multiple times

        engagement_score + frequency_bonus
      end

      def calculate_hashtag_consistency(posts)
        return 0 if posts.length < 2

        engagement_rates = posts.map { |p| p[:engagement_rate] }
        mean = engagement_rates.sum / engagement_rates.length
        variance = engagement_rates.map { |rate| (rate - mean) ** 2 }.sum / engagement_rates.length
        standard_deviation = Math.sqrt(variance)

        # Lower standard deviation = higher consistency
        # Convert to percentage (higher is better)
        consistency = 100 - (standard_deviation * 10)
        [consistency, 0].max.round(1)
      end

      def get_recommended_hashtag_mix(business_category)
        {
          branded: '2-3 hashtags',
          niche: '5-7 hashtags',
          community: '3-5 hashtags',
          trending: '2-3 hashtags',
          location: '1-2 hashtags',
          total_recommended: '15-20 hashtags'
        }
      end

      def get_content_specific_strategy(content_goals)
        strategies = {
          brand_awareness: 'Use trending and community hashtags for wider reach',
          engagement: 'Focus on niche hashtags that encourage interaction',
          sales: 'Include product-specific and shopping-related hashtags',
          community_building: 'Emphasize community and brand hashtags'
        }

        content_goals.map { |goal| { goal: goal, strategy: strategies[goal.to_sym] } }
      end

      def get_audience_targeted_hashtags(target_audience)
        # This would analyze target audience demographics and interests
        # Return relevant hashtags based on audience characteristics
        {
          demographic_hashtags: ['#millennials', '#genz', '#entrepreneurs'],
          interest_hashtags: ['#smallbusiness', '#ecommerce', '#onlineshopping'],
          behavior_hashtags: ['#shoppingonline', '#supportlocal', '#handmade']
        }
      end

      def get_hashtag_timing_recommendations
        {
          optimal_times: 'Post with trending hashtags during peak hours (11 AM - 1 PM, 7 PM - 9 PM)',
          hashtag_rotation: 'Rotate hashtags every 2-3 posts to avoid shadowbanning',
          hashtag_research_frequency: 'Research new hashtags weekly',
          performance_review: 'Review hashtag performance monthly'
        }
      end

      def get_hashtag_best_practices
        [
          'Use a mix of popular and niche hashtags',
          'Keep hashtags relevant to your content',
          'Research hashtags before using them',
          'Monitor hashtag performance regularly',
          'Avoid banned or flagged hashtags',
          'Create branded hashtags for campaigns',
          'Use hashtags in comments instead of captions for cleaner look',
          'Limit to 5-10 hashtags per post for better engagement'
        ]
      end

      def generate_hashtag_recommendation(all_suggestions, content_description)
        top_suggestions = all_suggestions.sort_by { |h| -h[:score] }.first(15)

        {
          recommended_hashtags: top_suggestions.map { |h| h[:name] }.join(' '),
          mix_breakdown: {
            high_competition: top_suggestions.count { |h| h[:difficulty] == 'high' },
            medium_competition: top_suggestions.count { |h| h[:difficulty] == 'medium' },
            low_competition: top_suggestions.count { |h| h[:difficulty] == 'low' }
          },
          expected_reach: top_suggestions.sum { |h| h[:estimated_reach] || 0 },
          confidence_score: calculate_confidence_score(top_suggestions, content_description)
        }
      end

      def calculate_confidence_score(suggestions, content_description)
        # Calculate confidence based on relevance and mix
        avg_relevance = suggestions.map { |s| s[:relevance_score] || s[:niche_relevance] || 50 }.sum / suggestions.length
        mix_quality = suggestions.group_by { |s| s[:difficulty] }.keys.length * 20 # Better mix = higher score

        [(avg_relevance + mix_quality) / 2, 100].min.round
      end

      def generate_implementation_plan(strategy)
        [
          {
            phase: 'Week 1-2',
            action: 'Research and compile initial hashtag lists',
            focus: 'Brand and niche hashtags'
          },
          {
            phase: 'Week 3-4',
            action: 'Test hashtag performance with A/B testing',
            focus: 'Community and trending hashtags'
          },
          {
            phase: 'Month 2',
            action: 'Optimize based on performance data',
            focus: 'Refine hashtag mix and strategy'
          },
          {
            phase: 'Ongoing',
            action: 'Monitor and adjust strategy monthly',
            focus: 'Continuous optimization'
          }
        ]
      end

      def get_monitoring_recommendations
        [
          'Track engagement rate changes after hashtag implementation',
          'Monitor reach and impressions weekly',
          'Analyze which hashtags drive the most profile visits',
          'Check for shadowbanning by monitoring hashtag visibility',
          'Review competitor hashtag strategies monthly',
          'Update trending hashtags weekly'
        ]
      end
    end
  end
end