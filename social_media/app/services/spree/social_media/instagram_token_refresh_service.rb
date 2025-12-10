require 'httparty'

module Spree
  module SocialMedia
    # Service to refresh Instagram long-lived access tokens
    # Long-lived tokens are valid for 60 days and can be refreshed
    # https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/
    class InstagramTokenRefreshService
      include HTTParty
      base_uri 'https://graph.instagram.com'

      def initialize(social_media_account)
        @account = social_media_account
        @access_token = @account.access_token
      end

      # Refresh a long-lived access token for another 60 days
      # Requirements:
      # - Token must be at least 24 hours old
      # - Token must not be expired
      # - Account must have instagram_business_basic permission
      def refresh_token
        # Check if token can be refreshed
        unless can_refresh?
          Rails.logger.warn "Instagram token for account #{@account.id} cannot be refreshed yet"
          return { success: false, error: 'Token cannot be refreshed yet (must be at least 24 hours old and not expired)' }
        end

        begin
          response = self.class.get('/refresh_access_token',
            query: {
              grant_type: 'ig_refresh_token',
              access_token: @access_token
            }
          )

          if response.success? && response.parsed_response['access_token']
            new_token = response.parsed_response['access_token']
            expires_in = response.parsed_response['expires_in']
            new_expires_at = Time.current + expires_in.seconds

            # Update account with new token
            @account.update!(
              access_token: new_token,
              expires_at: new_expires_at,
              last_sync_at: Time.current,
              last_error: nil,
              last_error_at: nil,
              token_metadata: @account.token_metadata.merge(
                token_refreshed_at: Time.current.iso8601,
                previous_expires_at: @account.expires_at.iso8601,
                new_expires_at: new_expires_at.iso8601,
                expires_in: expires_in
              )
            )

            Rails.logger.info "Instagram token refreshed successfully for account #{@account.id}. New expiration: #{new_expires_at}"

            {
              success: true,
              access_token: new_token,
              expires_at: new_expires_at,
              expires_in: expires_in
            }
          else
            error_message = parse_error(response)
            Rails.logger.error "Failed to refresh Instagram token for account #{@account.id}: #{error_message}"

            @account.update(
              last_error: "Token refresh failed: #{error_message}",
              last_error_at: Time.current
            )

            { success: false, error: error_message }
          end

        rescue => e
          Rails.logger.error "Instagram token refresh error: #{e.message}"
          Rails.error.report(e, context: { account_id: @account.id })

          @account.update(
            last_error: "Token refresh exception: #{e.message}",
            last_error_at: Time.current
          )

          { success: false, error: e.message }
        end
      end

      # Check if the token can be refreshed
      def can_refresh?
        return false unless @account.expires_at.present?
        return false if @account.expires_at < Time.current # Already expired

        # Token must be at least 24 hours old to be refreshed
        token_age = Time.current - (@account.token_metadata['obtained_at']&.to_time || @account.created_at)
        token_age >= 24.hours
      end

      # Check if token needs refreshing (within 7 days of expiration)
      def needs_refresh?
        return false unless @account.expires_at.present?

        days_until_expiration = (@account.expires_at - Time.current) / 1.day
        days_until_expiration <= 7 && days_until_expiration > 0
      end

      # Check if token is expired
      def expired?
        @account.expires_at.present? && @account.expires_at < Time.current
      end

      private

      def parse_error(response)
        error_data = response.parsed_response
        if error_data.is_a?(Hash) && error_data['error']
          if error_data['error'].is_a?(Hash)
            "#{error_data['error']['message']} (Code: #{error_data['error']['code']})"
          else
            error_data['error'].to_s
          end
        else
          "Instagram API error: #{response.code}"
        end
      end
    end
  end
end
