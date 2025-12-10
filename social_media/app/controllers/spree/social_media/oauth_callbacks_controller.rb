module Spree
  module SocialMedia
    class OauthCallbacksController < Spree::StoreController
      before_action :authenticate_user!
      before_action :load_vendor

      def create
        provider = params[:provider]
        auth_data = request.env['omniauth.auth']

        Rails.logger.info "OAuth callback received for #{provider}"
        Rails.logger.debug "Auth data: #{auth_data.inspect}"

        case provider
        when 'facebook'
          handle_facebook_callback(auth_data)
        when 'google_oauth2'
          handle_youtube_callback(auth_data)
        when 'tiktok'
          handle_tiktok_callback(auth_data)
        else
          redirect_with_error("Unsupported platform: #{provider}")
        end
      end

      def failure
        error_message = params[:message] || 'Authentication failed'
        Rails.logger.error "OAuth failure: #{error_message}"
        redirect_with_error("Social media authentication failed: #{error_message}")
      end

      private


      def load_vendor
        vendor_id = params[:vendor_id] || session[:vendor_id]

        @vendor = if vendor_id
                    Spree::Vendor.find(vendor_id)
                  elsif spree_current_user&.vendor
                    spree_current_user.vendor
                  else
                    Spree::Vendor.first # Fallback for single vendor setups
                  end

        unless @vendor
          redirect_with_error('No vendor account found. Please contact support.')
        end
      end

      def handle_facebook_callback(auth_data)
        begin
          # Extract Facebook user data from OmniAuth hash
          facebook_user_id = auth_data.uid
          access_token = auth_data.credentials.token
          expires_at = auth_data.credentials.expires_at ? Time.at(auth_data.credentials.expires_at) : nil
          user_info = auth_data.info

          Rails.logger.info "Facebook OAuth successful for user #{facebook_user_id}"

          # Get user's Facebook Pages (required for Instagram Business integration)
          pages_data = get_facebook_pages(access_token)

          if pages_data.empty?
            redirect_with_error('No Facebook pages found. Please create a Facebook page to connect Instagram Business accounts.')
            return
          end

          # For multi-page accounts, use the first page or let user choose
          # TODO: In the future, allow users to select which page to connect
          selected_page = pages_data.first
          page_access_token = selected_page['access_token']

          Rails.logger.info "Selected Facebook Page: #{selected_page['name']} (ID: #{selected_page['id']})"

          # Create or update Facebook account
          facebook_account = @vendor.social_media_accounts
                                   .facebook_accounts
                                   .find_or_initialize_by(platform_user_id: selected_page['id'])

          facebook_account.assign_attributes(
            access_token: page_access_token, # Use Page Access Token (not User Access Token)
            username: selected_page['name'],
            display_name: selected_page['name'],
            page_id: selected_page['id'],
            page_name: selected_page['name'],
            expires_at: expires_at,
            status: 'active',
            token_metadata: {
              user_access_token: access_token,
              page_access_token: page_access_token,
              facebook_user_id: facebook_user_id,
              expires_at: expires_at,
              scope: auth_data.credentials.params['scope'],
              page_category: selected_page['category']
            }
          )

          if facebook_account.save
            Rails.logger.info "Facebook account saved successfully (Account ID: #{facebook_account.id})"

            # Check if we should also connect Instagram
            # Instagram Business accounts MUST be connected to a Facebook Page
            if session[:connect_instagram] == 'true' || params[:connect_instagram] == 'true'
              handle_instagram_connection(facebook_account, page_access_token)
            end

            # Sync account details in background
            Spree::SocialMedia::SyncAccountDetailsJob.perform_later(facebook_account.id)

            # Clear session data
            session.delete(:connect_instagram)

            redirect_with_success("Facebook page '#{selected_page['name']}' connected successfully!")
          else
            Rails.logger.error "Failed to save Facebook account: #{facebook_account.errors.full_messages.join(', ')}"
            redirect_with_error("Failed to connect Facebook account: #{facebook_account.errors.full_messages.join(', ')}")
          end

        rescue => e
          Rails.logger.error "Facebook OAuth callback error: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          Rails.error.report(e, context: { vendor_id: @vendor.id, provider: 'facebook' })
          redirect_with_error('Failed to connect Facebook account. Please try again.')
        end
      end

      def handle_instagram_connection(facebook_account, page_access_token)
        begin
          Rails.logger.info "Attempting to connect Instagram Business account for Facebook Page #{facebook_account.page_id}"

          # Get connected Instagram business account via Facebook Page
          # Note: Instagram Business accounts must be linked to a Facebook Page
          facebook_service = Spree::SocialMedia::FacebookApiService.new(facebook_account)
          instagram_data = facebook_service.get_connected_instagram_account

          if instagram_data
            Rails.logger.info "Instagram Business account found: @#{instagram_data['username']} (ID: #{instagram_data['id']})"

            # Create or update Instagram account
            instagram_account = @vendor.social_media_accounts
                                      .instagram_accounts
                                      .find_or_initialize_by(platform_user_id: instagram_data['id'])

            instagram_account.assign_attributes(
              access_token: page_access_token, # Use Page Access Token for Instagram API calls
              username: instagram_data['username'],
              display_name: instagram_data['name'] || instagram_data['username'],
              followers_count: instagram_data['followers_count'] || 0,
              posts_count: instagram_data['media_count'] || 0,
              expires_at: facebook_account.expires_at,
              status: 'active',
              token_metadata: {
                facebook_page_id: facebook_account.page_id,
                facebook_page_name: facebook_account.page_name,
                connected_via_facebook: true,
                page_access_token: page_access_token
              }
            )

            if instagram_account.save
              Rails.logger.info "Instagram account saved successfully (Account ID: #{instagram_account.id})"
              flash[:notice] = (flash[:notice] || '') + " Instagram account @#{instagram_data['username']} also connected!"

              # Sync Instagram account details in background
              Spree::SocialMedia::SyncAccountDetailsJob.perform_later(instagram_account.id)
            else
              Rails.logger.error "Failed to save Instagram account: #{instagram_account.errors.full_messages.join(', ')}"
              flash[:alert] = "Instagram connection failed: #{instagram_account.errors.full_messages.join(', ')}"
            end
          else
            Rails.logger.info "No Instagram Business account connected to Facebook Page #{facebook_account.page_name}. Please link an Instagram Business account to your Facebook Page."
            flash[:alert] = "No Instagram Business account found. Please connect an Instagram Business account to your Facebook Page first."
          end

        rescue => e
          Rails.logger.error "Instagram connection error: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          Rails.error.report(e, context: { vendor_id: @vendor.id, facebook_page_id: facebook_account.page_id })
          flash[:alert] = "Instagram connection failed: #{e.message}"
          # Don't fail the Facebook connection if Instagram fails
        end
      end

      def handle_youtube_callback(auth_data)
        begin
          # Extract YouTube/Google data
          google_user_id = auth_data.uid
          access_token = auth_data.credentials.token
          refresh_token = auth_data.credentials.refresh_token
          expires_at = Time.at(auth_data.credentials.expires_at)

          # Get YouTube channel information
          channel_data = get_youtube_channel_data(access_token)

          unless channel_data
            redirect_with_error('No YouTube channel found. Please create a YouTube channel first.')
            return
          end

          # Create or update YouTube account
          youtube_account = @vendor.social_media_accounts
                                  .youtube_accounts
                                  .find_or_initialize_by(platform_user_id: channel_data['id'])

          youtube_account.assign_attributes(
            access_token: access_token,
            refresh_token: refresh_token,
            expires_at: expires_at,
            username: channel_data['snippet']['title'],
            display_name: channel_data['snippet']['title'],
            bio: channel_data['snippet']['description'],
            followers_count: channel_data['statistics']['subscriberCount'],
            posts_count: channel_data['statistics']['videoCount'],
            status: 'active',
            token_metadata: {
              google_user_id: google_user_id,
              channel_id: channel_data['id'],
              scope: auth_data.credentials.scope
            }
          )

          if youtube_account.save
            # Sync account details in background
            Spree::SocialMedia::SyncAccountDetailsJob.perform_later(youtube_account.id)

            redirect_with_success("YouTube channel '#{channel_data['snippet']['title']}' connected successfully!")
          else
            redirect_with_error("Failed to connect YouTube account: #{youtube_account.errors.full_messages.join(', ')}")
          end

        rescue => e
          Rails.logger.error "YouTube OAuth callback error: #{e.message}"
          Rails.error.report(e, context: { vendor_id: @vendor.id, provider: 'youtube' })
          redirect_with_error('Failed to connect YouTube account. Please try again.')
        end
      end

      def handle_tiktok_callback(auth_data)
        begin
          # TikTok implementation would go here
          # Note: TikTok Business API has different requirements and approval process

          tiktok_user_id = auth_data.uid
          access_token = auth_data.credentials.token
          refresh_token = auth_data.credentials.refresh_token

          # Create TikTok account (pending approval)
          tiktok_account = @vendor.social_media_accounts
                                 .tiktok_accounts
                                 .find_or_initialize_by(platform_user_id: tiktok_user_id)

          tiktok_account.assign_attributes(
            access_token: access_token,
            refresh_token: refresh_token,
            username: auth_data.info.nickname,
            display_name: auth_data.info.name,
            status: 'pending_approval', # TikTok requires manual approval
            token_metadata: {
              scope: auth_data.credentials.scope
            }
          )

          if tiktok_account.save
            redirect_with_success('TikTok account connected! Your account is pending approval from TikTok Business.')
          else
            redirect_with_error("Failed to connect TikTok account: #{tiktok_account.errors.full_messages.join(', ')}")
          end

        rescue => e
          Rails.logger.error "TikTok OAuth callback error: #{e.message}"
          Rails.error.report(e, context: { vendor_id: @vendor.id, provider: 'tiktok' })
          redirect_with_error('Failed to connect TikTok account. Please try again.')
        end
      end

      # Helper methods
      def get_facebook_pages(access_token)
        response = HTTParty.get('https://graph.facebook.com/v22.0/me/accounts',
          query: {
            fields: 'id,name,access_token,category,tasks,instagram_business_account',
            access_token: access_token
          }
        )

        if response.success? && response.parsed_response['data']
          pages = response.parsed_response['data']

          # Filter pages that have MANAGE and CREATE_CONTENT permissions
          pages.select do |page|
            tasks = page['tasks'] || []
            tasks.include?('MANAGE') && tasks.include?('CREATE_CONTENT')
          end
        else
          Rails.logger.error "Failed to get Facebook pages: #{response.parsed_response}"
          []
        end
      rescue => e
        Rails.logger.error "Failed to get Facebook pages: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        []
      end

      def get_youtube_channel_data(access_token)
        response = HTTParty.get('https://www.googleapis.com/youtube/v3/channels',
          query: {
            part: 'snippet,statistics',
            mine: true,
            access_token: access_token
          }
        )

        if response.success? && response.parsed_response['items']&.any?
          response.parsed_response['items'].first
        else
          nil
        end
      rescue => e
        Rails.logger.error "Failed to get YouTube channel data: #{e.message}"
        nil
      end

      def redirect_with_success(message)
        flash[:success] = message
        redirect_to spree.admin_social_media_path
      end

      def redirect_with_error(message)
        flash[:error] = message
        redirect_to spree.admin_social_media_path
      end
    end
  end
end