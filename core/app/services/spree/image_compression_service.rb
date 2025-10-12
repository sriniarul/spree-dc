require 'mini_magick'

module Spree
  class ImageCompressionService
    def initialize(attachment_or_file, max_file_size: nil, compression_quality: nil, max_width: nil, max_height: nil)
      @attachment_or_file = attachment_or_file
      @max_file_size = max_file_size || Spree::Config.image_compression.max_file_size
      @compression_quality = compression_quality || Spree::Config.image_compression.compression_quality
      @max_width = max_width || Spree::Config.image_compression.max_width
      @max_height = max_height || Spree::Config.image_compression.max_height
    end

    def call
      return @attachment_or_file unless needs_compression?
      return @attachment_or_file unless Spree::Config.image_compression.enabled

      compress_image
    end

    def needs_compression?
      file_size = if @attachment_or_file.respond_to?(:byte_size)
                    @attachment_or_file.byte_size
                  elsif @attachment_or_file.respond_to?(:size)
                    @attachment_or_file.size
                  else
                    File.size(@attachment_or_file.path) if @attachment_or_file.respond_to?(:path)
                  end

      file_size && file_size > @max_file_size
    end

    private

    def compress_image
      image = MiniMagick::Image.read(image_blob)

      # Resize if dimensions exceed limits
      if image.width > @max_width || image.height > @max_height
        image.resize "#{@max_width}x#{@max_height}>"
      end

      # Reduce quality for JPEG images
      if %w[jpeg jpg].include?(image.type.downcase)
        image.quality(@compression_quality * 100)
      end

      # Strip metadata to reduce size
      image.strip

      # Create a new StringIO with compressed data
      compressed_data = StringIO.new(image.to_blob)
      compressed_data.define_singleton_method(:original_filename) { original_filename }
      compressed_data.define_singleton_method(:content_type) { content_type }

      compressed_data
    end

    def image_blob
      if @attachment_or_file.respond_to?(:download)
        @attachment_or_file.download
      elsif @attachment_or_file.respond_to?(:read)
        @attachment_or_file.read
      else
        File.read(@attachment_or_file.path)
      end
    end

    def original_filename
      if @attachment_or_file.respond_to?(:filename)
        @attachment_or_file.filename.to_s
      elsif @attachment_or_file.respond_to?(:original_filename)
        @attachment_or_file.original_filename
      else
        'compressed_image.jpg'
      end
    end

    def content_type
      if @attachment_or_file.respond_to?(:content_type)
        @attachment_or_file.content_type
      else
        'image/jpeg'
      end
    end
  end
end