module Spree
  module SocialMedia
    class MediaProcessor
      include Rails.application.routes.url_helpers

      attr_reader :social_media_post, :errors, :processed_media

      # Instagram media requirements
      INSTAGRAM_IMAGE_FORMATS = %w[jpg jpeg png].freeze
      INSTAGRAM_VIDEO_FORMATS = %w[mp4 mov].freeze

      # Image processing settings
      MAX_IMAGE_DIMENSION = 1080
      MIN_IMAGE_DIMENSION = 320
      JPEG_QUALITY = 85

      # Video processing settings
      MAX_VIDEO_BITRATE = 25_000_000 # 25 Mbps
      MAX_VIDEO_DURATION = 60 # seconds for feed
      STORY_VIDEO_DURATION = 15 # seconds for stories
      REEL_VIDEO_DURATION = 90 # seconds for reels

      def initialize(social_media_post)
        @social_media_post = social_media_post
        @errors = []
        @processed_media = []
      end

      def process_all_media
        return false unless @social_media_post.media_attachments.any?

        success = true

        @social_media_post.media_attachments.each_with_index do |attachment, index|
          begin
            processed = process_single_media(attachment, index)
            @processed_media << processed if processed
          rescue => e
            @errors << "Media #{index + 1}: #{e.message}"
            success = false
          end
        end

        success && @errors.empty?
      end

      def generate_thumbnails
        @processed_media.each do |media_info|
          next unless media_info[:type] == 'video'

          begin
            thumbnail_path = generate_video_thumbnail(media_info[:attachment])
            media_info[:thumbnail_url] = thumbnail_path if thumbnail_path
          rescue => e
            Rails.logger.warn "Failed to generate thumbnail for video: #{e.message}"
          end
        end
      end

      def optimize_for_platform(platform = 'instagram')
        case platform.to_s
        when 'instagram'
          optimize_for_instagram
        when 'facebook'
          optimize_for_facebook
        when 'youtube'
          optimize_for_youtube
        else
          @errors << "Unsupported platform: #{platform}"
          false
        end
      end

      def media_urls
        @processed_media.map { |media| media[:public_url] }.compact
      end

      def media_metadata
        @processed_media.map do |media|
          {
            url: media[:public_url],
            type: media[:type],
            format: media[:format],
            dimensions: media[:dimensions],
            duration: media[:duration],
            size_bytes: media[:size_bytes],
            thumbnail_url: media[:thumbnail_url]
          }
        end
      end

      private

      def process_single_media(attachment, index)
        content_type = attachment.content_type
        filename = attachment.filename.to_s.downcase

        media_info = {
          attachment: attachment,
          index: index,
          original_filename: attachment.filename.to_s,
          content_type: content_type,
          size_bytes: attachment.byte_size
        }

        if image_content_type?(content_type)
          process_image(media_info)
        elsif video_content_type?(content_type)
          process_video(media_info)
        else
          raise "Unsupported media type: #{content_type}"
        end

        # Generate public URL for the processed media
        media_info[:public_url] = generate_public_url(attachment)
        media_info
      end

      def process_image(media_info)
        attachment = media_info[:attachment]

        # Get image metadata using MiniMagick if available
        if defined?(MiniMagick)
          begin
            attachment.open do |file|
              image = MiniMagick::Image.new(file.path)

              media_info.merge!(
                type: 'image',
                format: image.type.downcase,
                dimensions: {
                  width: image.width,
                  height: image.height
                }
              )

              # Process image for Instagram optimization
              if should_optimize_image?(image)
                optimized_image = optimize_image(image, media_info[:index])
                media_info[:optimized] = true
                media_info[:optimization_notes] = get_optimization_notes(image)
              end
            end
          rescue => e
            Rails.logger.warn "Failed to process image with MiniMagick: #{e.message}"
            # Fallback to basic info
            media_info.merge!(
              type: 'image',
              format: File.extname(attachment.filename.to_s).delete('.').downcase,
              dimensions: { width: nil, height: nil }
            )
          end
        else
          # Basic processing without MiniMagick
          media_info.merge!(
            type: 'image',
            format: File.extname(attachment.filename.to_s).delete('.').downcase,
            dimensions: { width: nil, height: nil }
          )
        end

        validate_image_requirements(media_info)
      end

      def process_video(media_info)
        attachment = media_info[:attachment]

        media_info.merge!(
          type: 'video',
          format: File.extname(attachment.filename.to_s).delete('.').downcase,
          dimensions: { width: nil, height: nil },
          duration: nil
        )

        # Extract video metadata if FFmpeg tools are available
        if system('which ffprobe > /dev/null 2>&1')
          begin
            attachment.open do |file|
              metadata = extract_video_metadata(file.path)
              media_info.merge!(metadata)
            end
          rescue => e
            Rails.logger.warn "Failed to extract video metadata: #{e.message}"
          end
        end

        validate_video_requirements(media_info)
      end

      def should_optimize_image?(image)
        # Check if image needs optimization
        return true if image.width > MAX_IMAGE_DIMENSION || image.height > MAX_IMAGE_DIMENSION
        return true if image.type.downcase == 'png' && @social_media_post.social_media_account.platform == 'instagram'
        return true if image.size > 8.megabytes
        false
      end

      def optimize_image(image, index)
        content_type = @social_media_post.content_type&.to_sym

        case content_type
        when :story
          optimize_for_story(image, index)
        when :feed, nil
          optimize_for_feed(image, index)
        when :reel
          # Reels typically use video, but if image provided, treat as feed
          optimize_for_feed(image, index)
        end
      end

      def optimize_for_story(image, index)
        # Instagram Stories: 9:16 aspect ratio, 1080x1920 optimal
        target_width = 1080
        target_height = 1920

        image.resize "#{target_width}x#{target_height}^"
        image.gravity 'center'
        image.extent "#{target_width}x#{target_height}"
        image.format 'jpg'
        image.quality JPEG_QUALITY
      end

      def optimize_for_feed(image, index)
        # Instagram Feed: Square (1:1) or portrait (4:5) work best
        current_aspect_ratio = image.width.to_f / image.height

        if current_aspect_ratio > 1.91 || current_aspect_ratio < 0.8
          # Crop to 1:1 (square) if outside acceptable range
          min_dimension = [image.width, image.height].min
          image.resize "#{min_dimension}x#{min_dimension}^"
          image.gravity 'center'
          image.extent "#{min_dimension}x#{min_dimension}"
        end

        # Resize if too large
        if image.width > MAX_IMAGE_DIMENSION || image.height > MAX_IMAGE_DIMENSION
          image.resize "#{MAX_IMAGE_DIMENSION}x#{MAX_IMAGE_DIMENSION}>"
        end

        image.format 'jpg'
        image.quality JPEG_QUALITY
      end

      def extract_video_metadata(file_path)
        cmd = "ffprobe -v quiet -print_format json -show_format -show_streams \"#{file_path}\""
        output = `#{cmd}`

        return {} if output.blank?

        data = JSON.parse(output)
        video_stream = data['streams']&.find { |stream| stream['codec_type'] == 'video' }

        return {} unless video_stream

        {
          dimensions: {
            width: video_stream['width'],
            height: video_stream['height']
          },
          duration: data['format']['duration']&.to_f,
          bitrate: data['format']['bit_rate']&.to_i,
          codec: video_stream['codec_name'],
          fps: (eval(video_stream['r_frame_rate']) rescue nil)
        }
      rescue JSON::ParserError => e
        Rails.logger.warn "Failed to parse ffprobe output: #{e.message}"
        {}
      end

      def generate_video_thumbnail(attachment)
        return nil unless system('which ffmpeg > /dev/null 2>&1')

        attachment.open do |file|
          thumbnail_path = Rails.root.join('tmp', "thumbnail_#{SecureRandom.hex(8)}.jpg")

          cmd = "ffmpeg -i \"#{file.path}\" -ss 00:00:01.000 -vframes 1 -y \"#{thumbnail_path}\""

          if system(cmd)
            # Upload thumbnail as attachment if needed
            return thumbnail_path.to_s
          end
        end

        nil
      rescue => e
        Rails.logger.warn "Failed to generate video thumbnail: #{e.message}"
        nil
      end

      def validate_image_requirements(media_info)
        dimensions = media_info[:dimensions]

        if dimensions[:width] && dimensions[:height]
          if dimensions[:width] < MIN_IMAGE_DIMENSION || dimensions[:height] < MIN_IMAGE_DIMENSION
            @errors << "Image #{media_info[:index] + 1}: Dimensions too small (#{dimensions[:width]}x#{dimensions[:height]}). Minimum: #{MIN_IMAGE_DIMENSION}x#{MIN_IMAGE_DIMENSION}"
          end

          # Check aspect ratio for content type
          aspect_ratio = dimensions[:width].to_f / dimensions[:height]
          validate_aspect_ratio(aspect_ratio, media_info[:index] + 1)
        end

        # Check file size
        if media_info[:size_bytes] > 8.megabytes
          @errors << "Image #{media_info[:index] + 1}: File size too large (#{(media_info[:size_bytes] / 1.megabyte.to_f).round(1)}MB). Maximum: 8MB"
        end

        # Check format
        unless INSTAGRAM_IMAGE_FORMATS.include?(media_info[:format])
          @errors << "Image #{media_info[:index] + 1}: Unsupported format '#{media_info[:format]}'. Supported: #{INSTAGRAM_IMAGE_FORMATS.join(', ')}"
        end
      end

      def validate_video_requirements(media_info)
        # Check format
        unless INSTAGRAM_VIDEO_FORMATS.include?(media_info[:format])
          @errors << "Video #{media_info[:index] + 1}: Unsupported format '#{media_info[:format]}'. Supported: #{INSTAGRAM_VIDEO_FORMATS.join(', ')}"
        end

        # Check duration
        if media_info[:duration]
          max_duration = case @social_media_post.content_type&.to_sym
                        when :story
                          STORY_VIDEO_DURATION
                        when :reel
                          REEL_VIDEO_DURATION
                        else
                          MAX_VIDEO_DURATION
                        end

          if media_info[:duration] > max_duration
            @errors << "Video #{media_info[:index] + 1}: Duration too long (#{media_info[:duration]}s). Maximum for #{@social_media_post.content_type || 'feed'}: #{max_duration}s"
          end

          if media_info[:duration] < 3
            @errors << "Video #{media_info[:index] + 1}: Duration too short (#{media_info[:duration]}s). Minimum: 3s"
          end
        end

        # Check file size
        if media_info[:size_bytes] > 100.megabytes
          @errors << "Video #{media_info[:index] + 1}: File size too large (#{(media_info[:size_bytes] / 1.megabyte.to_f).round(1)}MB). Maximum: 100MB"
        end

        # Check aspect ratio if dimensions available
        if media_info[:dimensions][:width] && media_info[:dimensions][:height]
          aspect_ratio = media_info[:dimensions][:width].to_f / media_info[:dimensions][:height]
          validate_aspect_ratio(aspect_ratio, media_info[:index] + 1, 'video')
        end
      end

      def validate_aspect_ratio(aspect_ratio, position, type = 'image')
        case @social_media_post.content_type&.to_sym
        when :story
          unless (0.55..0.58).cover?(aspect_ratio) # 9:16 range
            @errors << "#{type.capitalize} #{position}: Stories require 9:16 aspect ratio (current: #{aspect_ratio.round(2)})"
          end
        when :reel
          unless (0.55..0.58).cover?(aspect_ratio) # 9:16 range
            @errors << "#{type.capitalize} #{position}: Reels require 9:16 aspect ratio (current: #{aspect_ratio.round(2)})"
          end
        when :feed, nil
          if aspect_ratio < 0.8 || aspect_ratio > 1.91
            @errors << "#{type.capitalize} #{position}: Feed posts work best with aspect ratios between 4:5 and 1.91:1 (current: #{aspect_ratio.round(2)})"
          end
        end
      end

      def get_optimization_notes(image)
        notes = []
        notes << "Resized to fit Instagram dimensions" if image.width > MAX_IMAGE_DIMENSION || image.height > MAX_IMAGE_DIMENSION
        notes << "Converted to JPEG for better compatibility" if image.type.downcase != 'jpeg'
        notes << "Compressed for optimal file size" if image.size > 5.megabytes
        notes
      end

      def generate_public_url(attachment)
        if attachment.respond_to?(:url)
          # Active Storage URL
          attachment.url
        elsif defined?(Rails.application.routes.url_helpers)
          # Generate URL using Rails URL helpers
          rails_blob_url(attachment, only_path: false)
        else
          # Fallback
          attachment.service_url rescue nil
        end
      end

      def optimize_for_instagram
        # Instagram-specific optimizations
        @processed_media.each do |media|
          media[:platform_optimized] = 'instagram'

          if media[:type] == 'image'
            # Ensure JPEG format for best Instagram compatibility
            if media[:format] != 'jpg' && media[:format] != 'jpeg'
              media[:conversion_needed] = true
              media[:target_format] = 'jpg'
            end
          end
        end
        true
      end

      def optimize_for_facebook
        # Facebook-specific optimizations
        true
      end

      def optimize_for_youtube
        # YouTube-specific optimizations (mainly for video)
        @processed_media.each do |media|
          if media[:type] == 'video'
            media[:platform_optimized] = 'youtube'

            # YouTube prefers MP4 format
            if media[:format] != 'mp4'
              media[:conversion_needed] = true
              media[:target_format] = 'mp4'
            end
          end
        end
        true
      end

      def image_content_type?(content_type)
        content_type.start_with?('image/')
      end

      def video_content_type?(content_type)
        content_type.start_with?('video/')
      end

      class ProcessingError < StandardError; end
    end
  end
end