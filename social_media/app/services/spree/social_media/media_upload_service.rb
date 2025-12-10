module Spree
  module SocialMedia
    class MediaUploadService

      def initialize(product = nil)
        @product = product
        @errors = []
      end

      # Process and upload media files for social media posting
      def process_media_for_post(files, platform, options = {})
        return { success: false, error: 'No files provided' } if files.blank?

        begin
          processed_media = []

          files.each do |file|
            result = process_single_file(file, platform, options)

            if result[:success]
              processed_media << result[:media_data]
            else
              @errors << result[:error]
            end
          end

          if processed_media.any?
            {
              success: true,
              media_urls: processed_media.map { |m| m[:url] },
              media_data: processed_media
            }
          else
            {
              success: false,
              error: @errors.join(', ')
            }
          end

        rescue => e
          Rails.logger.error "Media processing failed: #{e.message}"
          { success: false, error: e.message }
        end
      end

      # Generate product media from Spree product
      def generate_product_media(platform, options = {})
        return { success: false, error: 'No product provided' } unless @product

        begin
          media_files = []

          # Get product images
          if @product.images.attached?
            @product.images.limit(platform_media_limit(platform)).each do |image|
              processed_image = process_product_image(image, platform, options)
              media_files << processed_image if processed_image
            end
          end

          # Add product video if available and platform supports it
          if platform_supports_video?(platform) && @product.respond_to?(:videos) && @product.videos.attached?
            @product.videos.limit(1).each do |video|
              processed_video = process_product_video(video, platform, options)
              media_files << processed_video if processed_video
            end
          end

          # Generate product carousel image if no media found
          if media_files.empty?
            generated_image = generate_product_placeholder(platform, options)
            media_files << generated_image if generated_image
          end

          {
            success: true,
            media_urls: media_files.map { |m| m[:url] },
            media_data: media_files
          }

        rescue => e
          Rails.logger.error "Product media generation failed: #{e.message}"
          { success: false, error: e.message }
        end
      end

      # Create optimized image for platform
      def create_platform_optimized_image(image_url, platform, options = {})
        begin
          # Download original image
          downloaded_image = download_blob_to_tempfile(image_url)

          # Get platform-specific dimensions
          dimensions = get_platform_dimensions(platform, options[:content_type])

          # Process image using ImageProcessing
          processed_image = ImageProcessing::MiniMagick
            .source(downloaded_image)
            .resize_to_fill(dimensions[:width], dimensions[:height])
            .quality(options[:quality] || SpreeSocialMedia::Config.default_image_quality)
            .call

          # Upload to cloud storage (or local storage)
          uploaded_url = upload_processed_media(processed_image, platform, 'image')

          {
            success: true,
            url: uploaded_url,
            width: dimensions[:width],
            height: dimensions[:height],
            file_type: 'image'
          }

        rescue => e
          Rails.logger.error "Image optimization failed: #{e.message}"
          { success: false, error: e.message }
        end
      ensure
        # Clean up temporary files
        downloaded_image&.close
        processed_image&.close
      end

      # Validate media for platform
      def validate_media_for_platform(media_data, platform)
        validations = []

        media_data.each do |media|
          case platform
          when 'instagram'
            validations.concat(validate_instagram_media(media))
          when 'facebook'
            validations.concat(validate_facebook_media(media))
          when 'youtube'
            validations.concat(validate_youtube_media(media))
          when 'tiktok'
            validations.concat(validate_tiktok_media(media))
          end
        end

        if validations.any?
          { success: false, errors: validations }
        else
          { success: true }
        end
      end

      private

      def process_single_file(file, platform, options)
        # Determine file type
        if image_file?(file)
          process_image_file(file, platform, options)
        elsif video_file?(file)
          process_video_file(file, platform, options)
        else
          { success: false, error: 'Unsupported file type' }
        end
      end

      def process_image_file(file, platform, options)
        # Optimize image for platform
        result = create_platform_optimized_image(file, platform, options)

        if result[:success]
          {
            success: true,
            media_data: {
              url: result[:url],
              type: 'image',
              width: result[:width],
              height: result[:height],
              platform: platform
            }
          }
        else
          { success: false, error: result[:error] }
        end
      end

      def process_video_file(file, platform, options)
        unless platform_supports_video?(platform)
          return { success: false, error: "#{platform} does not support video posts" }
        end

        # For video files, we might need to:
        # 1. Validate duration
        # 2. Validate file size
        # 3. Transcode if necessary
        # 4. Generate thumbnail

        begin
          # Basic validation
          validation = validate_video_file(file, platform)
          return validation unless validation[:success]

          # Upload video (in real implementation, you might transcode first)
          uploaded_url = upload_processed_media(file, platform, 'video')

          {
            success: true,
            media_data: {
              url: uploaded_url,
              type: 'video',
              platform: platform,
              duration: get_video_duration(file)
            }
          }

        rescue => e
          { success: false, error: e.message }
        end
      end

      def process_product_image(image, platform, options)
        return nil unless image.attached?

        begin
          # Create optimized version for platform
          result = create_platform_optimized_image(image, platform, options)

          if result[:success]
            {
              url: result[:url],
              type: 'image',
              width: result[:width],
              height: result[:height],
              alt_text: @product.name,
              platform: platform
            }
          else
            nil
          end

        rescue => e
          Rails.logger.error "Product image processing failed: #{e.message}"
          nil
        end
      end

      def process_product_video(video, platform, options)
        return nil unless video.attached? && platform_supports_video?(platform)

        begin
          # Basic video processing
          uploaded_url = upload_processed_media(video, platform, 'video')

          {
            url: uploaded_url,
            type: 'video',
            alt_text: @product.name,
            platform: platform
          }

        rescue => e
          Rails.logger.error "Product video processing failed: #{e.message}"
          nil
        end
      end

      def generate_product_placeholder(platform, options)
        # Generate a simple product card image with product info
        begin
          dimensions = get_platform_dimensions(platform, 'feed')

          # Create a simple image with product name and price
          # This is a simplified example - you'd use ImageProcessing::MiniMagick for real generation
          placeholder_url = generate_product_card_image(@product, dimensions)

          {
            url: placeholder_url,
            type: 'image',
            width: dimensions[:width],
            height: dimensions[:height],
            generated: true,
            platform: platform
          }

        rescue => e
          Rails.logger.error "Placeholder generation failed: #{e.message}"
          nil
        end
      end

      # Platform-specific validations
      def validate_instagram_media(media)
        errors = []

        case media[:type]
        when 'image'
          errors << 'Instagram images must be at least 320px wide' if media[:width] < 320
          errors << 'Instagram images should have aspect ratio between 0.8 and 1.91' unless valid_instagram_aspect_ratio?(media)
        when 'video'
          errors << 'Instagram videos must be between 3 seconds and 60 seconds' unless valid_instagram_video_duration?(media)
          errors << 'Instagram video file size must be less than 100MB' unless valid_file_size?(media, 100.megabytes)
        end

        errors
      end

      def validate_facebook_media(media)
        errors = []

        case media[:type]
        when 'image'
          errors << 'Facebook images should be at least 720px wide for best quality' if media[:width] < 720
        when 'video'
          errors << 'Facebook videos must be less than 4GB' unless valid_file_size?(media, 4.gigabytes)
          errors << 'Facebook videos must be less than 240 minutes' unless valid_facebook_video_duration?(media)
        end

        errors
      end

      def validate_youtube_media(media)
        errors = []

        case media[:type]
        when 'video'
          errors << 'YouTube videos must be less than 256GB' unless valid_file_size?(media, 256.gigabytes)
          errors << 'YouTube videos must be less than 12 hours' unless valid_youtube_video_duration?(media)
        end

        errors
      end

      def validate_tiktok_media(media)
        errors = []

        case media[:type]
        when 'video'
          errors << 'TikTok videos must be between 15 seconds and 3 minutes' unless valid_tiktok_video_duration?(media)
          errors << 'TikTok video file size must be less than 287MB' unless valid_file_size?(media, 287.megabytes)
        end

        errors
      end

      # Platform dimensions
      def get_platform_dimensions(platform, content_type = 'feed')
        case platform
        when 'instagram'
          case content_type
          when 'story'
            { width: 1080, height: 1920 } # 9:16 aspect ratio
          when 'reel'
            { width: 1080, height: 1920 } # 9:16 aspect ratio
          else
            { width: 1080, height: 1080 } # Square for feed
          end
        when 'facebook'
          { width: 1200, height: 630 } # Recommended feed image size
        when 'youtube'
          { width: 1280, height: 720 } # HD thumbnail
        when 'tiktok'
          { width: 1080, height: 1920 } # 9:16 aspect ratio
        else
          { width: 1080, height: 1080 } # Default square
        end
      end

      def platform_media_limit(platform)
        case platform
        when 'instagram'
          10 # Instagram carousel limit
        when 'facebook'
          10 # Facebook multi-photo limit
        else
          5 # Conservative default
        end
      end

      def platform_supports_video?(platform)
        %w[instagram facebook youtube tiktok].include?(platform)
      end

      # File type detection
      def image_file?(file)
        return false unless file

        if file.respond_to?(:content_type)
          file.content_type&.start_with?('image/')
        else
          file.to_s.match?(/\.(jpg|jpeg|png|gif|webp)(\?.*)?$/i)
        end
      end

      def video_file?(file)
        return false unless file

        if file.respond_to?(:content_type)
          file.content_type&.start_with?('video/')
        else
          file.to_s.match?(/\.(mp4|mov|avi|mkv|webm)(\?.*)?$/i)
        end
      end

      # Validation helpers
      def valid_instagram_aspect_ratio?(media)
        return true unless media[:width] && media[:height]

        aspect_ratio = media[:width].to_f / media[:height].to_f
        aspect_ratio >= 0.8 && aspect_ratio <= 1.91
      end

      def valid_instagram_video_duration?(media)
        duration = media[:duration] || 30 # Default assumption
        duration >= 3 && duration <= 60
      end

      def valid_file_size?(media, max_size)
        # This would need to be implemented based on your storage solution
        true # Placeholder
      end

      def upload_processed_media(file, platform, media_type)
        # This would upload to your cloud storage service (S3, CloudFront, etc.)
        # For now, return a placeholder URL
        timestamp = Time.current.to_i
        "https://cdn.dimecart.lk/social_media/#{platform}/#{media_type}/#{timestamp}/processed.#{file_extension(file)}"
      end

      def file_extension(file)
        if file.respond_to?(:original_filename)
          File.extname(file.original_filename).delete('.')
        else
          'jpg'
        end
      end

      def download_blob_to_tempfile(blob)
        # Download Active Storage blob to tempfile
        tempfile = Tempfile.new(['social_media', File.extname(blob.filename.to_s)])
        tempfile.binmode

        # For Rails 7.2, use the blob.download method
        tempfile.write(blob.download)
        tempfile.rewind
        tempfile
      end

      def generate_product_card_image(product, dimensions)
        # Generate a product card image with MiniMagick
        # This is a placeholder - actual implementation would create branded product cards
        "https://cdn.dimecart.lk/generated/product_cards/#{product.id}/#{dimensions[:width]}x#{dimensions[:height]}.jpg"
      end

      def get_video_duration(video)
        # Extract video duration using ffmpeg or similar
        30 # Placeholder
      end
    end
  end
end