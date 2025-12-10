require 'httparty'

module Spree
  module SocialMedia
    class ContentModerationService
      include HTTParty

      def initialize(account)
        @account = account
        @vendor = account.vendor
      end

      def moderate_content(content_data)
        Rails.logger.info "Moderating content for account #{@account.username}"

        results = {
          passed: false,
          violations: [],
          recommendations: [],
          risk_level: 'low',
          auto_approved: false
        }

        begin
          # Text content moderation
          if content_data[:caption].present?
            text_results = moderate_text_content(content_data[:caption])
            results[:violations].concat(text_results[:violations])
            results[:recommendations].concat(text_results[:recommendations])
          end

          # Hashtag compliance check
          if content_data[:hashtags].present?
            hashtag_results = moderate_hashtags(content_data[:hashtags])
            results[:violations].concat(hashtag_results[:violations])
            results[:recommendations].concat(hashtag_results[:recommendations])
          end

          # Media content analysis
          if content_data[:media_urls].present?
            media_results = moderate_media_content(content_data[:media_urls])
            results[:violations].concat(media_results[:violations])
            results[:recommendations].concat(media_results[:recommendations])
          end

          # Brand safety checks
          brand_results = check_brand_safety(content_data)
          results[:violations].concat(brand_results[:violations])
          results[:recommendations].concat(brand_results[:recommendations])

          # Compliance with Instagram policies
          policy_results = check_instagram_policy_compliance(content_data)
          results[:violations].concat(policy_results[:violations])
          results[:recommendations].concat(policy_results[:recommendations])

          # Calculate overall risk level
          results[:risk_level] = calculate_risk_level(results[:violations])

          # Determine if content passes moderation
          results[:passed] = results[:violations].empty? || all_violations_minor?(results[:violations])

          # Auto-approval for low-risk content
          results[:auto_approved] = results[:passed] && results[:risk_level] == 'low'

          Rails.logger.info "Moderation complete: #{results[:risk_level]} risk, #{results[:violations].count} violations"

          results

        rescue => e
          Rails.logger.error "Content moderation failed: #{e.message}"
          {
            passed: false,
            violations: [{ type: 'moderation_error', message: 'Content moderation service unavailable' }],
            recommendations: [],
            risk_level: 'high',
            auto_approved: false,
            error: e.message
          }
        end
      end

      def moderate_comment(comment_data)
        Rails.logger.info "Moderating comment: #{comment_data[:text]&.truncate(50)}"

        results = {
          action: 'approve',
          violations: [],
          confidence: 0.0,
          requires_review: false
        }

        text = comment_data[:text] || ''

        # Spam detection
        spam_check = detect_spam_content(text)
        if spam_check[:is_spam]
          results[:violations] << {
            type: 'spam',
            severity: 'medium',
            message: spam_check[:reason],
            confidence: spam_check[:confidence]
          }
        end

        # Toxic content detection
        toxicity_check = detect_toxic_content(text)
        if toxicity_check[:is_toxic]
          results[:violations] << {
            type: 'toxic_content',
            severity: toxicity_check[:severity],
            message: 'Comment contains inappropriate language or harassment',
            confidence: toxicity_check[:confidence]
          }
        end

        # Promotional content detection
        promo_check = detect_promotional_content(text)
        if promo_check[:is_promotional]
          results[:violations] << {
            type: 'promotional',
            severity: 'low',
            message: 'Comment appears to contain promotional content',
            confidence: promo_check[:confidence]
          }
        end

        # Determine action based on violations
        results[:action] = determine_moderation_action(results[:violations])
        results[:confidence] = calculate_overall_confidence(results[:violations])
        results[:requires_review] = requires_human_review?(results[:violations], results[:confidence])

        results
      end

      def check_compliance_status(account_id = nil)
        account = account_id ? Spree::SocialMediaAccount.find(account_id) : @account

        status = {
          overall_status: 'compliant',
          issues: [],
          recommendations: [],
          last_check: Time.current
        }

        # Check account-level compliance
        account_issues = check_account_compliance(account)
        status[:issues].concat(account_issues[:violations])
        status[:recommendations].concat(account_issues[:recommendations])

        # Check recent content compliance
        recent_posts = account.social_media_posts.published.where('published_at > ?', 30.days.ago)
        content_issues = check_content_history_compliance(recent_posts)
        status[:issues].concat(content_issues[:violations])
        status[:recommendations].concat(content_issues[:recommendations])

        # Check engagement compliance
        engagement_issues = check_engagement_compliance(account)
        status[:issues].concat(engagement_issues[:violations])
        status[:recommendations].concat(engagement_issues[:recommendations])

        # Determine overall status
        if status[:issues].any? { |issue| issue[:severity] == 'critical' }
          status[:overall_status] = 'non_compliant'
        elsif status[:issues].any? { |issue| issue[:severity] == 'high' }
          status[:overall_status] = 'at_risk'
        elsif status[:issues].any?
          status[:overall_status] = 'minor_issues'
        end

        status
      end

      private

      def moderate_text_content(text)
        violations = []
        recommendations = []

        # Inappropriate language detection
        if contains_inappropriate_language?(text)
          violations << {
            type: 'inappropriate_language',
            severity: 'medium',
            message: 'Content contains inappropriate language'
          }
        end

        # Copyright content detection
        if contains_copyrighted_content?(text)
          violations << {
            type: 'copyright_concern',
            severity: 'high',
            message: 'Content may contain copyrighted material'
          }
        end

        # Misleading information detection
        if contains_misleading_claims?(text)
          violations << {
            type: 'misleading_information',
            severity: 'high',
            message: 'Content may contain misleading information'
          }
        end

        # Length and readability checks
        readability_issues = check_text_quality(text)
        recommendations.concat(readability_issues)

        { violations: violations, recommendations: recommendations }
      end

      def moderate_hashtags(hashtags)
        violations = []
        recommendations = []

        hashtags.each do |hashtag|
          clean_hashtag = hashtag.gsub('#', '').downcase

          # Banned hashtags check
          if banned_hashtag?(clean_hashtag)
            violations << {
              type: 'banned_hashtag',
              severity: 'high',
              message: "Hashtag '#{hashtag}' is banned or restricted",
              hashtag: hashtag
            }
          end

          # Shadowbanned hashtags check
          if shadowbanned_hashtag?(clean_hashtag)
            violations << {
              type: 'shadowbanned_hashtag',
              severity: 'medium',
              message: "Hashtag '#{hashtag}' may be shadowbanned",
              hashtag: hashtag
            }
          end
        end

        # Too many hashtags warning
        if hashtags.length > 30
          recommendations << {
            type: 'hashtag_limit',
            message: 'Instagram recommends using no more than 30 hashtags',
            current_count: hashtags.length
          }
        end

        # Hashtag relevance check
        if hashtags.length > 10
          relevance_issues = check_hashtag_relevance(hashtags)
          recommendations.concat(relevance_issues)
        end

        { violations: violations, recommendations: recommendations }
      end

      def moderate_media_content(media_urls)
        violations = []
        recommendations = []

        media_urls.each do |media_url|
          # Image analysis (would integrate with image recognition service)
          image_analysis = analyze_image_content(media_url)

          if image_analysis[:inappropriate_content]
            violations << {
              type: 'inappropriate_image',
              severity: 'high',
              message: 'Image may contain inappropriate content',
              media_url: media_url
            }
          end

          if image_analysis[:copyright_concern]
            violations << {
              type: 'image_copyright',
              severity: 'medium',
              message: 'Image may have copyright concerns',
              media_url: media_url
            }
          end

          # Technical quality checks
          quality_issues = check_media_quality(media_url)
          recommendations.concat(quality_issues)
        end

        { violations: violations, recommendations: recommendations }
      end

      def check_brand_safety(content_data)
        violations = []
        recommendations = []

        brand_guidelines = @vendor.brand_guidelines || {}

        # Brand voice consistency
        if brand_guidelines['voice_guidelines'].present?
          voice_compliance = check_brand_voice_compliance(content_data[:caption], brand_guidelines['voice_guidelines'])
          unless voice_compliance[:compliant]
            recommendations << {
              type: 'brand_voice',
              message: voice_compliance[:message]
            }
          end
        end

        # Brand keyword restrictions
        if brand_guidelines['restricted_keywords'].present?
          restricted_words = brand_guidelines['restricted_keywords']
          found_restrictions = find_restricted_keywords(content_data[:caption], restricted_words)

          found_restrictions.each do |word|
            violations << {
              type: 'restricted_keyword',
              severity: 'medium',
              message: "Content contains restricted keyword: '#{word}'"
            }
          end
        end

        { violations: violations, recommendations: recommendations }
      end

      def check_instagram_policy_compliance(content_data)
        violations = []
        recommendations = []

        # Community guidelines checks
        guidelines_check = check_community_guidelines(content_data)
        violations.concat(guidelines_check[:violations])

        # Terms of service compliance
        tos_check = check_terms_of_service(content_data)
        violations.concat(tos_check[:violations])

        # Advertising policies (if applicable)
        if content_data[:is_promotional]
          ad_policy_check = check_advertising_policies(content_data)
          violations.concat(ad_policy_check[:violations])
        end

        { violations: violations, recommendations: recommendations }
      end

      def detect_spam_content(text)
        spam_indicators = []
        confidence = 0.0

        # Excessive emoji usage
        emoji_count = text.scan(/[\u{1F600}-\u{1F6FF}]/).length
        if emoji_count > (text.length * 0.3)
          spam_indicators << 'excessive_emojis'
          confidence += 0.3
        end

        # Repeated characters or words
        if text.match?(/((.)\2{4,})|((\w+)\s+\4)/)
          spam_indicators << 'repeated_content'
          confidence += 0.4
        end

        # Common spam phrases
        spam_phrases = ['follow for follow', 'f4f', 'check my bio', 'link in bio', 'dm for collab']
        spam_phrases.each do |phrase|
          if text.downcase.include?(phrase)
            spam_indicators << 'spam_phrase'
            confidence += 0.5
          end
        end

        {
          is_spam: confidence > 0.6,
          confidence: [confidence, 1.0].min,
          reason: spam_indicators.join(', ')
        }
      end

      def detect_toxic_content(text)
        # This would integrate with toxicity detection APIs like Perspective API
        # For now, simple keyword-based detection

        toxic_keywords = {
          high: %w[hate attack harassment threat violence],
          medium: %w[stupid idiot loser fake spam],
          low: %w[annoying boring waste]
        }

        severity = 'none'
        confidence = 0.0
        found_keywords = []

        toxic_keywords.each do |level, keywords|
          keywords.each do |keyword|
            if text.downcase.include?(keyword)
              found_keywords << keyword
              case level
              when :high
                severity = 'high'
                confidence = 0.9
              when :medium
                severity = 'medium' if severity == 'none'
                confidence = [confidence, 0.7].max
              when :low
                severity = 'low' if severity == 'none'
                confidence = [confidence, 0.4].max
              end
            end
          end
        end

        {
          is_toxic: severity != 'none',
          severity: severity,
          confidence: confidence,
          keywords: found_keywords
        }
      end

      def detect_promotional_content(text)
        promo_indicators = []
        confidence = 0.0

        promo_keywords = ['buy', 'shop', 'discount', 'sale', 'offer', 'deal', 'promo', 'code']
        promo_keywords.each do |keyword|
          if text.downcase.include?(keyword)
            promo_indicators << keyword
            confidence += 0.2
          end
        end

        # URL patterns
        if text.match?(/https?:\/\//)
          promo_indicators << 'contains_url'
          confidence += 0.3
        end

        {
          is_promotional: confidence > 0.4,
          confidence: [confidence, 1.0].min,
          indicators: promo_indicators
        }
      end

      # Additional helper methods with simplified implementations
      def contains_inappropriate_language?(text)
        inappropriate_words = %w[spam fake scam illegal drugs violence]
        inappropriate_words.any? { |word| text.downcase.include?(word) }
      end

      def contains_copyrighted_content?(text)
        # Simple check for copyright indicators
        text.match?(/©|copyright|trademark|®|™/i)
      end

      def contains_misleading_claims?(text)
        misleading_phrases = ['guaranteed results', '100% effective', 'miracle cure', 'secret formula']
        misleading_phrases.any? { |phrase| text.downcase.include?(phrase) }
      end

      def banned_hashtag?(hashtag)
        # This would check against a database of banned hashtags
        banned_list = %w[hate violence spam fake illegal]
        banned_list.include?(hashtag)
      end

      def shadowbanned_hashtag?(hashtag)
        # This would check against known shadowbanned hashtags
        shadowbanned_list = %w[like4like follow4follow f4f]
        shadowbanned_list.include?(hashtag)
      end

      def calculate_risk_level(violations)
        return 'low' if violations.empty?

        high_severity_count = violations.count { |v| v[:severity] == 'high' }
        critical_severity_count = violations.count { |v| v[:severity] == 'critical' }

        if critical_severity_count > 0
          'critical'
        elsif high_severity_count > 2
          'high'
        elsif high_severity_count > 0
          'medium'
        else
          'low'
        end
      end

      def all_violations_minor?(violations)
        violations.all? { |v| v[:severity] == 'low' }
      end

      def determine_moderation_action(violations)
        return 'approve' if violations.empty?

        critical_violations = violations.select { |v| v[:severity] == 'critical' }
        high_violations = violations.select { |v| v[:severity] == 'high' }

        if critical_violations.any?
          'reject'
        elsif high_violations.count > 2
          'reject'
        elsif high_violations.any?
          'review'
        else
          'approve'
        end
      end

      def calculate_overall_confidence(violations)
        return 1.0 if violations.empty?

        confidences = violations.map { |v| v[:confidence] || 0.5 }
        confidences.sum / confidences.length
      end

      def requires_human_review?(violations, confidence)
        return false if violations.empty?

        high_severity_violations = violations.select { |v| v[:severity].in?(['high', 'critical']) }
        high_severity_violations.any? || confidence < 0.7
      end

      # Placeholder methods for complex checks that would require external services
      def check_text_quality(text)
        []
      end

      def analyze_image_content(media_url)
        { inappropriate_content: false, copyright_concern: false }
      end

      def check_media_quality(media_url)
        []
      end

      def check_hashtag_relevance(hashtags)
        []
      end

      def check_brand_voice_compliance(text, guidelines)
        { compliant: true, message: '' }
      end

      def find_restricted_keywords(text, restricted_words)
        restricted_words.select { |word| text.downcase.include?(word.downcase) }
      end

      def check_community_guidelines(content_data)
        { violations: [] }
      end

      def check_terms_of_service(content_data)
        { violations: [] }
      end

      def check_advertising_policies(content_data)
        { violations: [] }
      end

      def check_account_compliance(account)
        { violations: [], recommendations: [] }
      end

      def check_content_history_compliance(posts)
        { violations: [], recommendations: [] }
      end

      def check_engagement_compliance(account)
        { violations: [], recommendations: [] }
      end
    end
  end
end