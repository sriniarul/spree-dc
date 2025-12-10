module Spree
  module SocialMedia
    class InstagramPostValidator
      include ActiveModel::Validations

      attr_reader :post, :social_media_account, :errors, :warnings

      # Instagram platform limits and requirements
      MAX_CAPTION_LENGTH = 2200
      MAX_HASHTAGS = 30
      MIN_IMAGE_WIDTH = 320
      MIN_IMAGE_HEIGHT = 320
      MAX_IMAGE_WIDTH = 1080
      MAX_IMAGE_HEIGHT = 1080
      MAX_VIDEO_DURATION = 60 # seconds for feed posts
      MAX_STORY_VIDEO_DURATION = 15 # seconds for stories
      MAX_REEL_VIDEO_DURATION = 90 # seconds for reels
      SUPPORTED_IMAGE_FORMATS = %w[jpg jpeg png gif webp].freeze
      SUPPORTED_VIDEO_FORMATS = %w[mp4 mov].freeze
      MAX_CAROUSEL_ITEMS = 10
      MIN_VIDEO_DURATION = 3 # minimum 3 seconds for videos

      def initialize(post, social_media_account = nil)
        @post = post
        @social_media_account = social_media_account || post.social_media_account
        @errors = []
        @warnings = []
      end

      def valid?
        @errors.clear
        @warnings.clear

        validate_basic_requirements
        validate_content_type_specific
        validate_media_requirements
        validate_caption_and_hashtags
        validate_account_permissions
        validate_scheduling_requirements
        validate_compliance_rules

        @errors.empty?
      end

      def validate!
        unless valid?
          raise ValidationError, "Instagram post validation failed: #{@errors.join(', ')}"
        end
      end

      def validation_summary
        {
          valid: @errors.empty?,
          errors: @errors,
          warnings: @warnings,
          recommendations: generate_recommendations
        }
      end

      private

      def validate_basic_requirements
        if @post.caption.blank?
          @errors << "Caption cannot be blank"
        end

        unless @social_media_account&.platform == 'instagram'
          @errors << "Account must be an Instagram account"
        end

        unless @social_media_account&.active?
          @errors << "Instagram account is not active or connected"
        end

        if @post.media_attachments.blank?
          @errors << "Instagram posts require at least one image or video"
        end
      end

      def validate_content_type_specific
        case @post.content_type&.to_sym
        when :feed, nil
          validate_feed_post
        when :story
          validate_story_post
        when :reel
          validate_reel_post
        else
          @errors << "Unsupported content type: #{@post.content_type}"
        end
      end

      def validate_feed_post
        media_count = @post.media_attachments.size

        if media_count > MAX_CAROUSEL_ITEMS
          @errors << "Instagram carousel posts support maximum #{MAX_CAROUSEL_ITEMS} items (you have #{media_count})"
        end

        # Mixed media validation for carousel
        if media_count > 1
          has_images = @post.media_attachments.any? { |media| image_format?(media.filename) }
          has_videos = @post.media_attachments.any? { |media| video_format?(media.filename) }

          if has_images && has_videos
            @errors << "Instagram carousel posts cannot mix images and videos"
          end
        end
      end

      def validate_story_post
        media_count = @post.media_attachments.size

        if media_count != 1
          @errors << "Instagram stories support exactly 1 media item (you have #{media_count})"
        end

        media = @post.media_attachments.first
        if media && video_format?(media.filename)
          # Stories have different video duration limits
          @warnings << "Instagram story videos should be #{MAX_STORY_VIDEO_DURATION} seconds or less for optimal performance"
        end
      end

      def validate_reel_post
        media_count = @post.media_attachments.size

        if media_count != 1
          @errors << "Instagram reels support exactly 1 video (you have #{media_count})"
        end

        media = @post.media_attachments.first
        unless media && video_format?(media.filename)
          @errors << "Instagram reels require a video file"
        end
      end

      def validate_media_requirements
        @post.media_attachments.each_with_index do |media, index|
          validate_single_media(media, index + 1)
        end
      end

      def validate_single_media(media, position)
        filename = media.filename.to_s.downcase

        # File format validation
        unless supported_format?(filename)
          @errors << "Media #{position}: Unsupported file format. Supported formats: #{SUPPORTED_IMAGE_FORMATS.join(', ')} for images, #{SUPPORTED_VIDEO_FORMATS.join(', ')} for videos"
          return
        end

        # File size validation (if available)
        if media.respond_to?(:byte_size)
          validate_file_size(media, position)
        end

        # Dimension validation (if available)
        if media.respond_to?(:metadata) && media.metadata.present?
          validate_media_dimensions(media, position)
        else
          @warnings << "Media #{position}: Cannot validate dimensions - ensure images are at least #{MIN_IMAGE_WIDTH}x#{MIN_IMAGE_HEIGHT} pixels"
        end
      end

      def validate_file_size(media, position)
        max_size_mb = image_format?(media.filename) ? 8 : 100 # 8MB for images, 100MB for videos
        size_mb = media.byte_size / 1.megabyte.to_f

        if size_mb > max_size_mb
          @errors << "Media #{position}: File size (#{size_mb.round(1)}MB) exceeds maximum allowed (#{max_size_mb}MB)"
        end
      end

      def validate_media_dimensions(media, position)
        metadata = media.metadata
        width = metadata['width']
        height = metadata['height']

        return unless width && height

        if image_format?(media.filename)
          validate_image_dimensions(width, height, position)
        elsif video_format?(media.filename)
          validate_video_dimensions(width, height, position)
          validate_video_duration(metadata, position)
        end
      end

      def validate_image_dimensions(width, height, position)
        if width < MIN_IMAGE_WIDTH || height < MIN_IMAGE_HEIGHT
          @errors << "Image #{position}: Dimensions (#{width}x#{height}) below minimum requirement (#{MIN_IMAGE_WIDTH}x#{MIN_IMAGE_HEIGHT})"
        end

        # Aspect ratio recommendations
        aspect_ratio = width.to_f / height

        case @post.content_type&.to_sym
        when :story
          optimal_ratio = 9.0 / 16.0 # 9:16 for stories
          unless (0.55..0.58).cover?(aspect_ratio)
            @warnings << "Image #{position}: For optimal story display, use 9:16 aspect ratio (1080x1920 pixels)"
          end
        when :feed, nil
          # Square (1:1) or portrait (4:5) work best for feed
          if aspect_ratio < 0.8 || aspect_ratio > 1.91
            @warnings << "Image #{position}: Instagram feed works best with square (1:1) or portrait (4:5) aspect ratios"
          end
        end
      end

      def validate_video_dimensions(width, height, position)
        aspect_ratio = width.to_f / height

        case @post.content_type&.to_sym
        when :story
          unless (0.55..0.58).cover?(aspect_ratio)
            @warnings << "Video #{position}: Stories work best with 9:16 aspect ratio (1080x1920 pixels)"
          end
        when :reel
          unless (0.55..0.58).cover?(aspect_ratio)
            @warnings << "Video #{position}: Reels work best with 9:16 aspect ratio (1080x1920 pixels)"
          end
        when :feed, nil
          # Square or landscape acceptable for feed videos
          if aspect_ratio < 0.8 || aspect_ratio > 1.91
            @warnings << "Video #{position}: Feed videos work best with square to landscape aspect ratios"
          end
        end
      end

      def validate_video_duration(metadata, position)
        duration = metadata['duration']
        return unless duration

        duration_seconds = duration.to_f

        if duration_seconds < MIN_VIDEO_DURATION
          @errors << "Video #{position}: Duration (#{duration_seconds}s) is too short. Minimum #{MIN_VIDEO_DURATION} seconds required"
        end

        case @post.content_type&.to_sym
        when :story
          if duration_seconds > MAX_STORY_VIDEO_DURATION
            @warnings << "Video #{position}: Duration (#{duration_seconds}s) exceeds story limit (#{MAX_STORY_VIDEO_DURATION}s). Video will be truncated"
          end
        when :reel
          if duration_seconds > MAX_REEL_VIDEO_DURATION
            @errors << "Video #{position}: Duration (#{duration_seconds}s) exceeds reel limit (#{MAX_REEL_VIDEO_DURATION}s)"
          end
        when :feed, nil
          if duration_seconds > MAX_VIDEO_DURATION
            @errors << "Video #{position}: Duration (#{duration_seconds}s) exceeds feed video limit (#{MAX_VIDEO_DURATION}s)"
          end
        end
      end

      def validate_caption_and_hashtags
        caption_length = @post.caption.length

        if caption_length > MAX_CAPTION_LENGTH
          @errors << "Caption length (#{caption_length}) exceeds Instagram limit (#{MAX_CAPTION_LENGTH} characters)"
        end

        # Hashtag validation
        hashtags = extract_hashtags(@post.caption, @post.hashtags)

        if hashtags.size > MAX_HASHTAGS
          @errors << "Too many hashtags (#{hashtags.size}). Instagram allows maximum #{MAX_HASHTAGS} hashtags per post"
        end

        # Check for prohibited or flagged hashtags
        validate_hashtag_compliance(hashtags)

        # Caption quality recommendations
        if caption_length < 125
          @warnings << "Consider adding more context to your caption (currently #{caption_length} characters). Posts with engaging captions perform better"
        end
      end

      def validate_account_permissions
        return unless @social_media_account

        # Check account type
        unless @social_media_account.token_metadata&.dig('account_type') == 'BUSINESS'
          @warnings << "Instagram Business account required for optimal publishing features. Some features may be limited with Personal accounts"
        end

        # Check token expiration
        expires_at = @social_media_account.token_metadata&.dig('expires_at')
        if expires_at && Time.at(expires_at) < 1.week.from_now
          @warnings << "Instagram access token expires soon. Consider refreshing the connection"
        end

        # Check required permissions
        required_scopes = %w[instagram_basic instagram_content_publish]
        current_scopes = @social_media_account.token_metadata&.dig('scope')&.split(',') || []

        missing_scopes = required_scopes - current_scopes
        if missing_scopes.any?
          @errors << "Missing required Instagram permissions: #{missing_scopes.join(', ')}. Please reconnect your account"
        end
      end

      def validate_scheduling_requirements
        return unless @post.scheduled_at

        scheduled_time = @post.scheduled_at

        # Must be in the future
        if scheduled_time <= Time.current
          @errors << "Scheduled time must be in the future"
        end

        # Instagram API limitations on scheduling
        if scheduled_time > 75.days.from_now
          @errors << "Posts cannot be scheduled more than 75 days in advance"
        end

        # Stories cannot be scheduled through API
        if @post.content_type == 'story'
          @errors << "Instagram Stories cannot be scheduled and must be published immediately"
        end
      end

      def validate_compliance_rules
        # Content policy validation
        caption_lower = @post.caption.downcase

        # Check for promotional content compliance
        promotional_keywords = %w[buy now sale discount promotion limited offer]
        if promotional_keywords.any? { |keyword| caption_lower.include?(keyword) }
          @warnings << "Post contains promotional language. Ensure compliance with Instagram's promotional content policies"
        end

        # Check for sensitive content indicators
        sensitive_keywords = %w[weight loss diet supplement medical health claim]
        if sensitive_keywords.any? { |keyword| caption_lower.include?(keyword) }
          @warnings << "Post may contain sensitive content. Review Instagram's health and wellness policies"
        end

        # URL validation
        urls = @post.caption.scan(URI.regexp)
        if urls.size > 1
          @warnings << "Multiple URLs detected. Instagram algorithm may reduce reach for posts with multiple external links"
        end
      end

      def extract_hashtags(caption, hashtag_field = nil)
        # Extract hashtags from caption
        caption_hashtags = caption.scan(/#\w+/).map { |tag| tag.downcase }

        # Extract hashtags from dedicated hashtag field
        field_hashtags = []
        if hashtag_field.present?
          field_hashtags = hashtag_field.split(/[\s,]+/)
                                      .map { |tag| tag.gsub(/^#/, '').downcase }
                                      .map { |tag| "##{tag}" }
        end

        (caption_hashtags + field_hashtags).uniq
      end

      def validate_hashtag_compliance(hashtags)
        # Check for banned or flagged hashtags
        # This would typically check against a database of prohibited hashtags
        potentially_flagged = %w[#follow4follow #like4like #spam #bot]

        flagged_found = hashtags.select { |tag| potentially_flagged.include?(tag.downcase) }
        if flagged_found.any?
          @warnings << "Potentially flagged hashtags detected: #{flagged_found.join(', ')}. These may reduce post visibility"
        end

        # Check hashtag length
        long_hashtags = hashtags.select { |tag| tag.length > 30 }
        if long_hashtags.any?
          @warnings << "Very long hashtags may not be effective: #{long_hashtags.join(', ')}"
        end
      end

      def generate_recommendations
        recommendations = []

        # Media optimization recommendations
        if @post.media_attachments.size == 1 && image_format?(@post.media_attachments.first.filename)
          recommendations << "Consider adding multiple images to create a carousel post for higher engagement"
        end

        # Caption optimization
        if @post.caption.length < 50
          recommendations << "Add more descriptive content to your caption to improve engagement"
        end

        # Hashtag optimization
        hashtag_count = extract_hashtags(@post.caption, @post.hashtags).size
        if hashtag_count < 5
          recommendations << "Consider using 5-10 relevant hashtags to improve discoverability"
        elsif hashtag_count > 15
          recommendations << "Consider using fewer, more targeted hashtags (5-10) instead of the maximum 30"
        end

        # Timing recommendations
        if @post.scheduled_at.nil?
          recommendations << "Consider scheduling your post for optimal engagement times (typically 9-11 AM or 7-9 PM in your audience's timezone)"
        end

        recommendations
      end

      def supported_format?(filename)
        image_format?(filename) || video_format?(filename)
      end

      def image_format?(filename)
        extension = File.extname(filename.to_s).downcase.gsub('.', '')
        SUPPORTED_IMAGE_FORMATS.include?(extension)
      end

      def video_format?(filename)
        extension = File.extname(filename.to_s).downcase.gsub('.', '')
        SUPPORTED_VIDEO_FORMATS.include?(extension)
      end

      class ValidationError < StandardError; end
    end
  end
end