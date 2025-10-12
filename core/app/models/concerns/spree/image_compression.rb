module Spree
  module ImageCompression
    extend ActiveSupport::Concern

    included do
      before_save :compress_attachment_if_needed, if: -> { attachment.attached? && attachment.changed? }
    end

    private

    def compress_attachment_if_needed
      return unless attachment.attached?
      return unless Spree::Config.image_compression.enabled
      return unless Spree::Config.image_compression.compress_on_server

      compressed_attachment = Spree::ImageCompressionService.new(attachment.blob).call

      if compressed_attachment != attachment.blob
        # Replace the attachment with compressed version
        attachment.attach(compressed_attachment)
      end
    rescue StandardError => e
      Rails.logger.warn "Failed to compress image: #{e.message}"
      # Continue with original image if compression fails
    end
  end
end