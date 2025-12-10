require 'httparty'

module Spree
  module SocialMedia
    class WhatsappApiService
      include HTTParty
      base_uri 'https://graph.facebook.com'

      def initialize(social_media_account)
        @account = social_media_account
        @access_token = social_media_account.access_token
        @phone_number_id = social_media_account.token_metadata&.dig('phone_number_id')
      end

      def test_connection
        return false unless @access_token && @phone_number_id

        response = self.class.get("/v17.0/#{@phone_number_id}",
          query: { access_token: @access_token }
        )

        response.success? && !response.parsed_response['error']
      rescue => e
        Rails.logger.error "WhatsApp connection test failed: #{e.message}"
        false
      end

      def get_business_profile
        return nil unless @phone_number_id

        response = self.class.get("/v17.0/#{@phone_number_id}/whatsapp_business_profile",
          query: {
            fields: 'about,address,description,email,profile_picture_url,websites,vertical',
            access_token: @access_token
          }
        )

        if response.success? && response.parsed_response['data']&.any?
          response.parsed_response['data'].first
        else
          Rails.logger.error "Failed to get WhatsApp business profile: #{response.parsed_response}"
          nil
        end
      rescue => e
        Rails.logger.error "WhatsApp API error: #{e.message}"
        nil
      end

      def send_message(to_phone_number, message_text)
        return { success: false, error: 'Missing configuration' } unless @phone_number_id

        response = self.class.post("/v17.0/#{@phone_number_id}/messages",
          body: {
            messaging_product: 'whatsapp',
            to: to_phone_number,
            type: 'text',
            text: { body: message_text }
          }.to_json,
          headers: {
            'Authorization' => "Bearer #{@access_token}",
            'Content-Type' => 'application/json'
          }
        )

        if response.success?
          { success: true, message_id: response.parsed_response['messages']&.first&.dig('id') }
        else
          { success: false, error: response.parsed_response['error']&.dig('message') || 'Unknown error' }
        end
      rescue => e
        Rails.logger.error "WhatsApp send message error: #{e.message}"
        { success: false, error: e.message }
      end

      def send_template_message(to_phone_number, template_name, language_code = 'en_US', components = [])
        return { success: false, error: 'Missing configuration' } unless @phone_number_id

        response = self.class.post("/v17.0/#{@phone_number_id}/messages",
          body: {
            messaging_product: 'whatsapp',
            to: to_phone_number,
            type: 'template',
            template: {
              name: template_name,
              language: { code: language_code },
              components: components
            }
          }.to_json,
          headers: {
            'Authorization' => "Bearer #{@access_token}",
            'Content-Type' => 'application/json'
          }
        )

        if response.success?
          { success: true, message_id: response.parsed_response['messages']&.first&.dig('id') }
        else
          { success: false, error: response.parsed_response['error']&.dig('message') || 'Unknown error' }
        end
      rescue => e
        Rails.logger.error "WhatsApp template message error: #{e.message}"
        { success: false, error: e.message }
      end

      def get_analytics_data(start_date, end_date)
        # WhatsApp Business API doesn't provide detailed analytics like other platforms
        # You would typically track this data in your application
        Rails.logger.info "WhatsApp analytics tracking should be implemented in application layer"
        nil
      end

      def upload_media(file_path, media_type)
        return { success: false, error: 'Missing configuration' } unless @phone_number_id

        response = self.class.post("/v17.0/#{@phone_number_id}/media",
          body: {
            file: File.new(file_path),
            type: media_type,
            messaging_product: 'whatsapp'
          },
          headers: {
            'Authorization' => "Bearer #{@access_token}"
          }
        )

        if response.success?
          { success: true, media_id: response.parsed_response['id'] }
        else
          { success: false, error: response.parsed_response['error']&.dig('message') || 'Upload failed' }
        end
      rescue => e
        Rails.logger.error "WhatsApp media upload error: #{e.message}"
        { success: false, error: e.message }
      end

      private

      def headers
        {
          'Authorization' => "Bearer #{@access_token}",
          'Content-Type' => 'application/json'
        }
      end
    end
  end
end