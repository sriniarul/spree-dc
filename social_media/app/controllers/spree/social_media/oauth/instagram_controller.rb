module Spree
  module SocialMedia
    module Oauth
      class InstagramController < Spree::StoreController
        skip_before_action :verify_authenticity_token, only: [:callback]
        before_action :load_vendor

        # Instagram OAuth callback
        # https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/
        def callback
          # Step 1: Validate state parameter (CSRF protection)
          unless validate_state_token
            Rails.logger.error "Instagram OAuth: Invalid state token"
            redirect_with_error('Invalid state token. Please try again.')
            return
          end

          # Step 2: Handle authorization errors
          if params[:error].present?
            handle_authorization_error
            return
          end

          # Step 3: Get authorization code
          authorization_code = params[:code]
          unless authorization_code.present?
            redirect_with_error('No authorization code received from Instagram.')
            return
          end

          Rails.logger.info "Instagram OAuth: Received authorization code"

          begin
            # Step 4: Exchange code for short-lived access token
            short_lived_token_data = exchange_code_for_token(authorization_code)

            unless short_lived_token_data
              redirect_with_error('Failed to exchange authorization code for access token.')
              return
            end

            Rails.logger.info "Instagram OAuth: Received short-lived token for user #{short_lived_token_data['user_id']}"

            # Step 5: Exchange short-lived token for long-lived token
            long_lived_token_data = exchange_for_long_lived_token(short_lived_token_data['access_token'])

            unless long_lived_token_data
              redirect_with_error('Failed to exchange for long-lived access token.')
              return
            end

            Rails.logger.info "Instagram OAuth: Received long-lived token (expires in #{long_lived_token_data['expires_in']} seconds)"

            # Step 6: Get Instagram account details
            account_details = get_instagram_account_details(long_lived_token_data['access_token'])

            unless account_details
              redirect_with_error('Failed to retrieve Instagram account details.')
              return
            end

            Rails.logger.info "Instagram OAuth: Retrieved account details for @#{account_details['username']}"

            # Step 7: Create or update Instagram account
            create_or_update_instagram_account(
              user_id: short_lived_token_data['user_id'],
              access_token: long_lived_token_data['access_token'],
              expires_in: long_lived_token_data['expires_in'],
              account_details: account_details,
              permissions: short_lived_token_data['permissions']
            )

            # Clear session
            session.delete(:vendor_id)
            session.delete(:oauth_state)
            session.delete(:oauth_state_token)

            redirect_with_success("Instagram account @#{account_details['username']} connected successfully!")

          rescue => e
            Rails.logger.error "Instagram OAuth callback error: #{e.message}"
            Rails.logger.error e.backtrace.join("\n")
            Rails.error.report(e, context: { vendor_id: @vendor&.id, provider: 'instagram' })
            redirect_with_error("Failed to connect Instagram account: #{e.message}")
          end
        end

        private

        def load_vendor
          vendor_id = params[:vendor_id] || session[:vendor_id]

          @vendor = if vendor_id.present?
                      Spree::Vendor.find(vendor_id)
                    elsif spree_current_user&.vendor
                      spree_current_user.vendor
                    else
                      Spree::Vendor.first
                    end

          unless @vendor
            redirect_with_error('No vendor account found. Please contact support.')
          end
        end

        def validate_state_token
          received_state = params[:state]
          stored_state = session[:oauth_state_token]

          received_state.present? && stored_state.present? && received_state == stored_state
        end

        def handle_authorization_error
          error = params[:error]
          error_reason = params[:error_reason]
          error_description = params[:error_description]

          Rails.logger.error "Instagram OAuth error: #{error} - #{error_reason} - #{error_description}"

          case error
          when 'access_denied'
            redirect_with_error('Instagram authorization was denied. Please grant permissions to connect your account.')
          else
            redirect_with_error("Instagram authorization failed: #{error_description || error}")
          end
        end

        # Step 1: Exchange authorization code for short-lived access token
        # POST https://api.instagram.com/oauth/access_token
        def exchange_code_for_token(code)
          instagram_app_id = Rails.application.credentials.dig(:instagram, :app_id) || ENV['INSTAGRAM_APP_ID']
          instagram_app_secret = Rails.application.credentials.dig(:instagram, :app_secret) || ENV['INSTAGRAM_APP_SECRET']
          redirect_uri = instagram_callback_url

          Rails.logger.info "Exchanging code for token with client_id: #{instagram_app_id}"

          response = HTTParty.post('https://api.instagram.com/oauth/access_token',
            body: {
              client_id: instagram_app_id,
              client_secret: instagram_app_secret,
              grant_type: 'authorization_code',
              redirect_uri: redirect_uri,
              code: code
            },
            headers: {
              'Content-Type' => 'application/x-www-form-urlencoded'
            }
          )

          if response.success? && response.parsed_response['access_token']
            response.parsed_response
          else
            Rails.logger.error "Failed to exchange code for token: #{response.parsed_response}"
            Rails.logger.error "Response code: #{response.code}"
            Rails.logger.error "Response body: #{response.body}"
            nil
          end
        end

        # Step 2: Exchange short-lived token for long-lived token (valid for 60 days)
        # GET https://graph.instagram.com/access_token
        def exchange_for_long_lived_token(short_lived_token)
          instagram_app_secret = Rails.application.credentials.dig(:instagram, :app_secret) || ENV['INSTAGRAM_APP_SECRET']

          response = HTTParty.get('https://graph.instagram.com/access_token',
            query: {
              grant_type: 'ig_exchange_token',
              client_secret: instagram_app_secret,
              access_token: short_lived_token
            }
          )

          if response.success? && response.parsed_response['access_token']
            response.parsed_response
          else
            Rails.logger.error "Failed to exchange for long-lived token: #{response.parsed_response}"
            nil
          end
        end

        # Step 3: Get Instagram account details
        # GET https://graph.instagram.com/me
        def get_instagram_account_details(access_token)
          response = HTTParty.get('https://graph.instagram.com/me',
            query: {
              fields: 'id,username,account_type,media_count',
              access_token: access_token
            }
          )

          if response.success?
            response.parsed_response
          else
            Rails.logger.error "Failed to get Instagram account details: #{response.parsed_response}"
            nil
          end
        end

        # Step 4: Create or update Instagram account in database
        def create_or_update_instagram_account(user_id:, access_token:, expires_in:, account_details:, permissions:)
          # Use with_deleted to find even soft-deleted accounts
          instagram_account = @vendor.social_media_accounts
                                     .with_deleted
                                     .where(platform: 'instagram', platform_user_id: user_id)
                                     .first

          # Calculate expiration time (60 days from now)
          expires_at = Time.current + expires_in.seconds

          if instagram_account
            # Update existing account (including restoring soft-deleted ones)
            instagram_account.deleted_at = nil if instagram_account.deleted_at.present?
            instagram_account.assign_attributes(
              access_token: access_token,
              username: account_details['username'],
              display_name: account_details['username'],
              posts_count: account_details['media_count'] || 0,
              expires_at: expires_at,
              status: 'active',
              last_error: nil,
              last_error_at: nil,
              token_metadata: {
                auth_type: 'instagram_login',
                account_type: account_details['account_type'],
                permissions: permissions,
                token_type: 'long_lived',
                expires_in: expires_in,
                obtained_at: Time.current.iso8601
              }
            )
          else
            # Create new account
            instagram_account = @vendor.social_media_accounts.new(
              platform: 'instagram',
              platform_user_id: user_id,
              access_token: access_token,
              username: account_details['username'],
              display_name: account_details['username'],
              posts_count: account_details['media_count'] || 0,
              expires_at: expires_at,
              status: 'active',
              token_metadata: {
                auth_type: 'instagram_login',
                account_type: account_details['account_type'],
                permissions: permissions,
                token_type: 'long_lived',
                expires_in: expires_in,
                obtained_at: Time.current.iso8601
              }
            )
          end

          if instagram_account.save
            Rails.logger.info "Instagram account #{instagram_account.new_record? ? 'created' : 'updated'} successfully (Account ID: #{instagram_account.id})"

            # Sync account details in background
            Spree::SocialMedia::SyncAccountDetailsJob.perform_later(instagram_account.id) if defined?(Spree::SocialMedia::SyncAccountDetailsJob)

            true
          else
            Rails.logger.error "Failed to save Instagram account: #{instagram_account.errors.full_messages.join(', ')}"
            redirect_with_error("Failed to save Instagram account: #{instagram_account.errors.full_messages.join(', ')}")
            false
          end
        rescue ActiveRecord::RecordNotUnique => e
          Rails.logger.warn "Duplicate Instagram account detected, fetching existing account"
          # Handle race condition - another request already created the account
          instagram_account = @vendor.social_media_accounts
                                     .instagram_accounts
                                     .find_by(platform_user_id: user_id)
          if instagram_account
            Rails.logger.info "Using existing Instagram account (Account ID: #{instagram_account.id})"
            true
          else
            raise e
          end
        end

        def instagram_callback_url
          "#{request.protocol}#{request.host_with_port}/social_media/oauth/instagram/callback"
        end

        def redirect_with_success(message)
          flash[:success] = message
          redirect_to spree.admin_social_media_accounts_path
        end

        def redirect_with_error(message)
          flash[:error] = message
          redirect_to spree.admin_social_media_accounts_path
        end
      end
    end
  end
end
