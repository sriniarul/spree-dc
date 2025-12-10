module Spree
  module SocialMedia
    class InstagramReelService
      include HTTParty
      base_uri 'https://graph.facebook.com/v18.0'

      def initialize(social_media_account)
        @account = social_media_account
        @access_token = @account.access_token
        @instagram_business_account_id = @account.platform_account_id
        @errors = []
      end

      def publish_reel(reel_data)
        @errors.clear

        begin
          # Validate reel requirements
          unless valid_reel_data?(reel_data)
            return { success: false, errors: @errors }
          end

          # Upload video first
          video_upload_result = upload_reel_video(reel_data[:video])
          unless video_upload_result[:success]
            return video_upload_result
          end

          # Create reel container
          container_result = create_reel_container(reel_data, video_upload_result[:video_id])
          unless container_result[:success]
            return container_result
          end

          # Publish the reel
          publish_result = publish_reel_container(container_result[:container_id])

          if publish_result[:success]
            {
              success: true,
              reel_id: publish_result[:reel_id],
              video_id: video_upload_result[:video_id],
              container_id: container_result[:container_id]
            }
          else
            publish_result
          end

        rescue => e
          Rails.logger.error "Instagram reel publishing error: #{e.message}"
          { success: false, errors: ["Reel publishing failed: #{e.message}"] }
        end
      end

      def upload_reel_video(video_file)
        begin
          # Upload video to Facebook servers for processing
          upload_response = HTTParty.post(
            "#{self.class.base_uri}/#{@instagram_business_account_id}/media",
            body: {
              media_type: 'REELS',
              video_url: upload_to_temporary_storage(video_file),
              access_token: @access_token
            }
          )

          if upload_response.success?
            {
              success: true,
              video_id: upload_response['id']
            }
          else
            {
              success: false,
              errors: [upload_response.dig('error', 'message') || 'Video upload failed']
            }
          end

        rescue => e
          Rails.logger.error "Reel video upload error: #{e.message}"
          { success: false, errors: ["Video upload failed: #{e.message}"] }
        end
      end

      def create_reel_container(reel_data, video_id)
        container_params = {
          media_type: 'REELS',
          video_url: video_id,
          access_token: @access_token
        }

        # Add caption if present
        if reel_data[:caption].present?
          container_params[:caption] = reel_data[:caption]
        end

        # Add cover image if present
        if reel_data[:cover_image].present?
          container_params[:thumb_offset] = reel_data[:cover_offset] || 0
        end

        # Add audio settings
        if reel_data[:audio_name].present?
          container_params[:audio_name] = reel_data[:audio_name]
        end

        # Add location if present
        if reel_data[:location_id].present?
          container_params[:location_id] = reel_data[:location_id]
        end

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
            errors: [response.dig('error', 'message') || 'Failed to create reel container']
          }
        end
      end

      def publish_reel_container(container_id)
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
            reel_id: response['id']
          }
        else
          {
            success: false,
            errors: [response.dig('error', 'message') || 'Failed to publish reel']
          }
        end
      end

      def get_reel_insights(reel_id, metrics = nil)
        metrics ||= %w[
          comments likes plays reach saved shares total_interactions
          ig_reels_avg_watch_time ig_reels_video_view_total_time
        ]

        response = HTTParty.get(
          "#{self.class.base_uri}/#{reel_id}/insights",
          query: {
            metric: metrics.join(','),
            access_token: @access_token
          }
        )

        if response.success?
          {
            success: true,
            insights: response['data'],
            reel_id: reel_id
          }
        else
          {
            success: false,
            errors: [response.dig('error', 'message') || 'Failed to get reel insights']
          }
        end
      end

      def schedule_reel(reel_data, publish_time)
        # Instagram doesn't support reel scheduling through API
        # Create a scheduled job to publish later
        job_id = Spree::SocialMedia::PublishReelJob.perform_at(
          publish_time,
          @account.id,
          reel_data
        )

        {
          success: true,
          message: 'Reel scheduled successfully',
          job_id: job_id,
          scheduled_for: publish_time
        }
      end

      def validate_reel_requirements(video_file)
        validation_results = {
          valid: true,
          errors: [],
          warnings: []
        }

        return validation_results unless video_file

        # Get video info
        video_info = analyze_video_file(video_file)

        # Duration validation (3 seconds to 90 seconds)
        if video_info[:duration]
          if video_info[:duration] < 3
            validation_results[:errors] << 'Reel must be at least 3 seconds long'
            validation_results[:valid] = false
          elsif video_info[:duration] > 90
            validation_results[:errors] << 'Reel cannot be longer than 90 seconds'
            validation_results[:valid] = false
          end
        else
          validation_results[:warnings] << 'Could not determine video duration'
        end

        # File size validation (under 1GB)
        if video_info[:size] && video_info[:size] > 1.gigabyte
          validation_results[:errors] << 'Video file must be under 1GB'
          validation_results[:valid] = false
        end

        # Aspect ratio validation (should be vertical 9:16)
        if video_info[:width] && video_info[:height]
          aspect_ratio = video_info[:width].to_f / video_info[:height]
          if aspect_ratio > 0.7 # More horizontal than 9:16
            validation_results[:warnings] << 'Reels perform better with vertical orientation (9:16 aspect ratio)'
          end
        end

        # Resolution validation (minimum 720p)
        if video_info[:height] && video_info[:height] < 720
          validation_results[:warnings] << 'Video resolution should be at least 720p for better quality'
        end

        # Frame rate validation
        if video_info[:frame_rate] && video_info[:frame_rate] > 60
          validation_results[:warnings] << 'Frame rate above 60fps may not be supported'
        end

        validation_results
      end

      def get_trending_audio
        # Get trending audio tracks for reels
        # This would typically connect to Instagram's audio library API
        response = HTTParty.get(
          "#{self.class.base_uri}/ig_trending_audio",
          query: {
            access_token: @access_token,
            limit: 20
          }
        )

        if response.success?
          {
            success: true,
            audio_tracks: response['data'] || []
          }
        else
          {
            success: false,
            errors: ['Failed to get trending audio']
          }
        end
      end

      def search_audio(query, limit = 20)
        # Search for audio tracks
        response = HTTParty.get(
          "#{self.class.base_uri}/ig_audio_search",
          query: {
            q: query,
            access_token: @access_token,
            limit: limit
          }
        )

        if response.success?
          {
            success: true,
            audio_tracks: response['data'] || []
          }
        else
          {
            success: false,
            errors: ['Audio search failed']
          }
        end
      end

      def get_reel_performance_tips
        [
          {
            category: 'Video Quality',
            tips: [
              'Use high resolution (minimum 720p, ideally 1080p)',
              'Maintain vertical orientation (9:16 aspect ratio)',
              'Ensure good lighting and clear audio',
              'Keep videos between 15-30 seconds for best engagement'
            ]
          },
          {
            category: 'Content Strategy',
            tips: [
              'Hook viewers in the first 3 seconds',
              'Use trending audio or create original sounds',
              'Include captions for accessibility',
              'End with a call-to-action or question'
            ]
          },
          {
            category: 'Posting Optimization',
            tips: [
              'Post when your audience is most active',
              'Use relevant hashtags (5-10 max)',
              'Engage with comments quickly after posting',
              'Share to your story to increase reach'
            ]
          },
          {
            category: 'Technical Tips',
            tips: [
              'Compress videos to reduce upload time',
              'Test playback before publishing',
              'Avoid copyrighted music without permission',
              'Consider adding auto-generated captions'
            ]
          }
        ]
      end

      def generate_reel_hashtags(video_content_description)
        # Generate relevant hashtags for reel content
        base_hashtags = %w[#reels #instagram #viral #trending #explore]

        content_hashtags = case video_content_description.downcase
                          when /fashion|style|outfit/
                            %w[#fashion #style #ootd #fashionista #styleinspo]
                          when /food|recipe|cooking/
                            %w[#food #foodie #recipe #cooking #delicious]
                          when /fitness|workout|gym/
                            %w[#fitness #workout #motivation #gym #health]
                          when /beauty|makeup|skincare/
                            %w[#beauty #makeup #skincare #beautytips #tutorial]
                          when /travel|adventure/
                            %w[#travel #adventure #wanderlust #explore #nature]
                          when /business|entrepreneur/
                            %w[#business #entrepreneur #success #motivation #tips]
                          else
                            %w[#creative #inspiration #lifestyle #content #amazing]
                          end

        {
          recommended_hashtags: (base_hashtags + content_hashtags).uniq,
          trending_hashtags: get_trending_hashtags_for_reels,
          niche_hashtags: generate_niche_hashtags(video_content_description)
        }
      end

      def optimize_reel_caption(original_caption, target_audience = 'general')
        optimizations = []
        optimized_caption = original_caption.dup

        # Add hook if missing
        unless optimized_caption.match?(/^(Watch|See|Learn|Discover|Find out)/i)
          hooks = ['👀 Watch this!', '🔥 You need to see this!', '✨ Here\'s how:', '💡 Did you know?']
          optimized_caption = "#{hooks.sample}\n\n#{optimized_caption}"
          optimizations << 'Added engaging hook'
        end

        # Add call-to-action if missing
        cta_keywords = %w[like comment share follow save try buy visit]
        unless cta_keywords.any? { |word| optimized_caption.downcase.include?(word) }
          ctas = [
            '💬 What do you think? Comment below!',
            '❤️ Double tap if you agree!',
            '📥 Save this for later!',
            '👥 Tag someone who needs to see this!'
          ]
          optimized_caption += "\n\n#{ctas.sample}"
          optimizations << 'Added call-to-action'
        end

        # Add emojis if sparse
        emoji_count = optimized_caption.scan(/[\u{1F600}-\u{1F64F}]|[\u{1F300}-\u{1F5FF}]|[\u{1F680}-\u{1F6FF}]|[\u{1F1E0}-\u{1F1FF}]/).length
        if emoji_count < 3
          optimized_caption = add_relevant_emojis(optimized_caption)
          optimizations << 'Added relevant emojis'
        end

        {
          original: original_caption,
          optimized: optimized_caption,
          improvements: optimizations,
          character_count: optimized_caption.length,
          estimated_engagement_boost: optimizations.length * 15 # Rough estimate
        }
      end

      private

      def valid_reel_data?(reel_data)
        # Check required fields
        unless reel_data[:video].present?
          @errors << 'Video file is required for reels'
          return false
        end

        # Validate video requirements
        validation_result = validate_reel_requirements(reel_data[:video])
        unless validation_result[:valid]
          @errors.concat(validation_result[:errors])
          return false
        end

        true
      end

      def analyze_video_file(video_file)
        info = {
          duration: nil,
          size: nil,
          width: nil,
          height: nil,
          frame_rate: nil,
          format: nil
        }

        return info unless video_file

        begin
          if video_file.respond_to?(:blob)
            info[:size] = video_file.blob.byte_size
            metadata = video_file.blob.metadata || {}

            info[:width] = metadata['width']
            info[:height] = metadata['height']
            info[:duration] = metadata['duration']
            info[:frame_rate] = metadata['frame_rate']
          elsif video_file.respond_to?(:size)
            info[:size] = video_file.size
          end

        rescue => e
          Rails.logger.warn "Could not analyze video file: #{e.message}"
        end

        info
      end

      def upload_to_temporary_storage(video_file)
        # Upload to temporary storage and return public URL
        # In production, implement proper file upload to S3 or similar
        "https://your-temp-storage.com/#{SecureRandom.uuid}"
      end

      def get_trending_hashtags_for_reels
        # This would connect to trending hashtags APIs
        %w[#trending #viral #fyp #foryou #reelsinstagram #instareels #explore]
      end

      def generate_niche_hashtags(description)
        keywords = description.downcase.split(/\s+/)
        niche_tags = []

        keywords.each do |keyword|
          next if keyword.length < 3
          niche_tags << "##{keyword}"
          niche_tags << "##{keyword}reels"
          niche_tags << "##{keyword}tips" if rand < 0.3
        end

        niche_tags.uniq.first(10)
      end

      def add_relevant_emojis(text)
        emoji_map = {
          /\b(amazing|awesome|great|fantastic)\b/i => '🔥',
          /\b(love|heart|favorite)\b/i => '❤️',
          /\b(new|fresh|latest)\b/i => '✨',
          /\b(tip|hack|secret)\b/i => '💡',
          /\b(money|cash|profit|earn)\b/i => '💰',
          /\b(time|quick|fast|speed)\b/i => '⚡',
          /\b(beautiful|pretty|stunning)\b/i => '😍',
          /\b(food|eat|delicious)\b/i => '🍴',
          /\b(work|job|business)\b/i => '💼',
          /\b(home|house)\b/i => '🏠'
        }

        enhanced_text = text.dup
        emoji_map.each do |pattern, emoji|
          if enhanced_text.match?(pattern) && !enhanced_text.include?(emoji)
            enhanced_text.gsub!(pattern) { |match| "#{match} #{emoji}" }
            break # Add only one emoji per pass
          end
        end

        enhanced_text
      end
    end
  end
end