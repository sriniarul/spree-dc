module Spree
  module SocialMedia
    class InstagramStoryService
      include HTTParty
      base_uri 'https://graph.facebook.com/v18.0'

      def initialize(social_media_account)
        @account = social_media_account
        @access_token = @account.access_token
        @instagram_business_account_id = @account.platform_account_id
        @errors = []
      end

      def publish_story(story_data)
        @errors.clear

        begin
          # Validate story requirements
          unless valid_story_data?(story_data)
            return { success: false, errors: @errors }
          end

          # Upload media first
          media_upload_result = upload_story_media(story_data[:media])
          unless media_upload_result[:success]
            return media_upload_result
          end

          # Create story container
          container_result = create_story_container(story_data, media_upload_result[:media_id])
          unless container_result[:success]
            return container_result
          end

          # Publish the story
          publish_result = publish_story_container(container_result[:container_id])

          if publish_result[:success]
            {
              success: true,
              story_id: publish_result[:story_id],
              media_id: media_upload_result[:media_id],
              container_id: container_result[:container_id]
            }
          else
            publish_result
          end

        rescue => e
          Rails.logger.error "Instagram story publishing error: #{e.message}"
          { success: false, errors: ["Story publishing failed: #{e.message}"] }
        end
      end

      def upload_story_media(media_file)
        begin
          # Determine media type
          media_type = get_media_type(media_file)

          case media_type
          when 'IMAGE'
            upload_story_image(media_file)
          when 'VIDEO'
            upload_story_video(media_file)
          else
            { success: false, errors: ['Unsupported media type for stories'] }
          end

        rescue => e
          Rails.logger.error "Story media upload error: #{e.message}"
          { success: false, errors: ["Media upload failed: #{e.message}"] }
        end
      end

      def create_story_container(story_data, media_id)
        container_params = {
          media_type: story_data[:media_type],
          access_token: @access_token
        }

        # Add media ID
        if story_data[:media_type] == 'IMAGE'
          container_params[:image_url] = media_id
        else
          container_params[:video_url] = media_id
        end

        # Add story-specific parameters
        container_params.merge!(build_story_params(story_data))

        response = HTTParty.post(
          "#{self.class.base_uri}/#{@instagram_business_account_id}/media",
          body: container_params
        )

        if response.success?
          {
            success: true,
            container_id: response['id']
          }
        else
          {
            success: false,
            errors: [response.dig('error', 'message') || 'Failed to create story container']
          }
        end
      end

      def publish_story_container(container_id)
        response = HTTParty.post(
          "#{self.class.base_uri}/#{@instagram_business_account_id}/media_publish",
          body: {
            creation_id: container_id,
            access_token: @access_token
          }
        )

        if response.success?
          {
            success: true,
            story_id: response['id']
          }
        else
          {
            success: false,
            errors: [response.dig('error', 'message') || 'Failed to publish story']
          }
        end
      end

      def get_story_insights(story_id, metrics = nil)
        metrics ||= %w[exits impressions reach replies story_navigation_actions]

        response = HTTParty.get(
          "#{self.class.base_uri}/#{story_id}/insights",
          query: {
            metric: metrics.join(','),
            access_token: @access_token
          }
        )

        if response.success?
          {
            success: true,
            insights: response['data'],
            story_id: story_id
          }
        else
          {
            success: false,
            errors: [response.dig('error', 'message') || 'Failed to get story insights']
          }
        end
      end

      def schedule_story(story_data, publish_time)
        # Note: Instagram doesn't support story scheduling through API
        # This creates a scheduled job to publish later

        job_id = Spree::SocialMedia::PublishStoryJob.perform_at(
          publish_time,
          @account.id,
          story_data
        )

        {
          success: true,
          message: 'Story scheduled successfully',
          job_id: job_id,
          scheduled_for: publish_time
        }
      end

      def add_story_sticker(story_data, sticker_data)
        # Add interactive stickers to stories
        stickers = story_data[:stickers] || []
        stickers << sticker_data

        story_data.merge(stickers: stickers)
      end

      def create_story_poll(question, options)
        {
          sticker_type: 'poll',
          question: question,
          options: options,
          position: { x: 0.5, y: 0.7 } # Center bottom
        }
      end

      def create_story_question_sticker(question)
        {
          sticker_type: 'question',
          question: question,
          background_color: '#FFFFFF',
          position: { x: 0.5, y: 0.8 }
        }
      end

      def create_story_countdown(title, end_time)
        {
          sticker_type: 'countdown',
          title: title,
          end_time: end_time.to_i,
          position: { x: 0.5, y: 0.3 }
        }
      end

      def validate_story_requirements(media_file)
        validation_results = {
          valid: true,
          errors: [],
          warnings: []
        }

        return validation_results unless media_file

        # Get media info
        media_info = analyze_media_file(media_file)

        # Validate image stories
        if media_info[:type] == 'image'
          # Instagram Stories should be 1080x1920 (9:16 aspect ratio)
          if media_info[:width] && media_info[:height]
            aspect_ratio = media_info[:width].to_f / media_info[:height]
            unless (0.5..0.7).cover?(aspect_ratio)
              validation_results[:warnings] << 'Image aspect ratio should be 9:16 for optimal story display'
            end
          end

          # File size should be under 30MB
          if media_info[:size] && media_info[:size] > 30.megabytes
            validation_results[:errors] << 'Image file size must be under 30MB'
            validation_results[:valid] = false
          end
        end

        # Validate video stories
        if media_info[:type] == 'video'
          # Duration should be 15 seconds or less
          if media_info[:duration] && media_info[:duration] > 15
            validation_results[:errors] << 'Video stories must be 15 seconds or shorter'
            validation_results[:valid] = false
          end

          # File size should be under 100MB
          if media_info[:size] && media_info[:size] > 100.megabytes
            validation_results[:errors] << 'Video file size must be under 100MB'
            validation_results[:valid] = false
          end

          # Aspect ratio check
          if media_info[:width] && media_info[:height]
            aspect_ratio = media_info[:width].to_f / media_info[:height]
            unless (0.5..0.7).cover?(aspect_ratio)
              validation_results[:warnings] << 'Video aspect ratio should be 9:16 for optimal story display'
            end
          end
        end

        validation_results
      end

      private

      def valid_story_data?(story_data)
        # Check required fields
        unless story_data[:media].present?
          @errors << 'Media file is required for stories'
          return false
        end

        unless story_data[:media_type].present?
          @errors << 'Media type is required'
          return false
        end

        # Validate media type
        unless %w[IMAGE VIDEO].include?(story_data[:media_type])
          @errors << 'Media type must be IMAGE or VIDEO'
          return false
        end

        # Validate story-specific requirements
        validation_result = validate_story_requirements(story_data[:media])
        unless validation_result[:valid]
          @errors.concat(validation_result[:errors])
          return false
        end

        true
      end

      def upload_story_image(image_file)
        # Upload image to Facebook/Instagram servers
        response = HTTParty.post(
          "#{self.class.base_uri}/#{@instagram_business_account_id}/media",
          body: {
            image_url: upload_to_temporary_storage(image_file),
            media_type: 'STORIES',
            access_token: @access_token
          }
        )

        if response.success?
          {
            success: true,
            media_id: response['id']
          }
        else
          {
            success: false,
            errors: [response.dig('error', 'message') || 'Image upload failed']
          }
        end
      end

      def upload_story_video(video_file)
        # Upload video to Facebook/Instagram servers
        response = HTTParty.post(
          "#{self.class.base_uri}/#{@instagram_business_account_id}/media",
          body: {
            video_url: upload_to_temporary_storage(video_file),
            media_type: 'STORIES',
            access_token: @access_token
          }
        )

        if response.success?
          {
            success: true,
            media_id: response['id']
          }
        else
          {
            success: false,
            errors: [response.dig('error', 'message') || 'Video upload failed']
          }
        end
      end

      def build_story_params(story_data)
        params = {}

        # Add text overlay if present
        if story_data[:text_overlay].present?
          params[:caption] = story_data[:text_overlay]
        end

        # Add stickers if present
        if story_data[:stickers].present?
          params.merge!(build_stickers_params(story_data[:stickers]))
        end

        # Add story-specific settings
        params[:media_type] = 'STORIES'

        params
      end

      def build_stickers_params(stickers)
        sticker_params = {}

        stickers.each_with_index do |sticker, index|
          case sticker[:sticker_type]
          when 'poll'
            sticker_params["poll_#{index}"] = {
              question: sticker[:question],
              options: sticker[:options],
              x: sticker.dig(:position, :x) || 0.5,
              y: sticker.dig(:position, :y) || 0.5
            }
          when 'question'
            sticker_params["question_#{index}"] = {
              question: sticker[:question],
              background_color: sticker[:background_color] || '#FFFFFF',
              x: sticker.dig(:position, :x) || 0.5,
              y: sticker.dig(:position, :y) || 0.5
            }
          when 'countdown'
            sticker_params["countdown_#{index}"] = {
              title: sticker[:title],
              end_time: sticker[:end_time],
              x: sticker.dig(:position, :x) || 0.5,
              y: sticker.dig(:position, :y) || 0.5
            }
          end
        end

        sticker_params
      end

      def get_media_type(media_file)
        return nil unless media_file

        content_type = if media_file.respond_to?(:content_type)
                        media_file.content_type
                      elsif media_file.respond_to?(:blob)
                        media_file.blob.content_type
                      else
                        'application/octet-stream'
                      end

        case content_type
        when /^image\//
          'IMAGE'
        when /^video\//
          'VIDEO'
        else
          nil
        end
      end

      def analyze_media_file(media_file)
        info = { type: nil, size: nil, width: nil, height: nil, duration: nil }

        return info unless media_file

        begin
          if media_file.respond_to?(:blob)
            info[:size] = media_file.blob.byte_size
            metadata = media_file.blob.metadata || {}

            info[:width] = metadata['width']
            info[:height] = metadata['height']
            info[:duration] = metadata['duration']

            content_type = media_file.blob.content_type
          elsif media_file.respond_to?(:size)
            info[:size] = media_file.size
          end

          content_type ||= media_file.content_type if media_file.respond_to?(:content_type)

          if content_type
            info[:type] = content_type.start_with?('image/') ? 'image' : 'video'
          end

        rescue => e
          Rails.logger.warn "Could not analyze media file: #{e.message}"
        end

        info
      end

      def upload_to_temporary_storage(media_file)
        # This would typically upload to a temporary storage service like AWS S3
        # and return a publicly accessible URL for Facebook to download

        # For now, return a placeholder URL
        # In production, implement proper temporary file storage
        "https://your-temp-storage.com/#{SecureRandom.uuid}"
      end
    end
  end
end