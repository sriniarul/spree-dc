module Spree
  module Admin
    module SocialMedia
      class AccountsController < Spree::Admin::BaseController
        before_action :load_vendor
        before_action :authorize_social_media_access
        before_action :load_account, only: [:show, :edit, :update, :destroy, :sync_analytics, :test_connection]

        def index
          @accounts = @vendor.social_media_accounts.includes(:social_media_analytics)
          @accounts = @accounts.by_platform(params[:platform]) if params[:platform].present?
        end

        def show
          @recent_posts = @account.social_media_posts.recent.limit(10)
          @analytics = @account.social_media_analytics.order(date: :desc).limit(30)
        end

        def new
          redirect_to oauth_path_for_platform(params[:platform]), allow_other_host: true, turbo: false
        end

        def edit
          # Edit account settings
        end

        def update
          if @account.update(account_params)
            flash[:success] = flash_message_for(@account, :successfully_updated)
            redirect_to spree.admin_social_media_account_path(@account)
          else
            render :edit
          end
        end

        def destroy
          if @account.destroy
            flash[:success] = flash_message_for(@account, :successfully_removed)
          else
            flash[:error] = @account.errors.full_messages.join(', ')
          end
          redirect_to spree.admin_social_media_path
        end

        def sync_analytics
          if @account.active?
            Spree::SocialMedia::SyncAnalyticsJob.perform_later(@account.id)
            flash[:success] = Spree.t('admin.social_media.analytics_sync_scheduled')
          else
            flash[:error] = Spree.t('admin.social_media.account_not_active')
          end
          redirect_back(fallback_location: spree.admin_social_media_account_path(@account))
        end

        def test_connection
          result = test_account_connection(@account)
          if result[:success]
            flash[:success] = Spree.t('admin.social_media.connection_test_success')
            @account.activate! if @account.error?
          else
            flash[:error] = Spree.t('admin.social_media.connection_test_failed', error: result[:error])
            @account.mark_error!(result[:error])
          end
          redirect_back(fallback_location: spree.admin_social_media_account_path(@account))
        end

        private

        def authorize_social_media_access
          authorize! :read, :social_media_dashboard
        end

        def load_vendor
          @vendor = if respond_to?(:current_vendor) && current_vendor.present?
                     current_vendor
                   else
                     try_spree_current_user&.vendor || Spree::Vendor.first
                   end

          unless @vendor
            flash[:error] = Spree.t(:no_vendor_associated)
            redirect_to spree.admin_root_path
          end
        end

        def load_account
          @account = @vendor.social_media_accounts.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          flash[:error] = Spree.t('admin.social_media.account_not_found')
          redirect_to spree.admin_social_media_path
        end

        def account_params
          params.require(:social_media_account).permit(
            :username, :display_name, :bio, :website_url, :auto_post_enabled,
            :analytics_enabled, :post_template
          )
        end

        def oauth_path_for_platform(platform)
          case platform
          when 'facebook'
            "/auth/facebook?vendor_id=#{@vendor.id}"
          when 'instagram'
            # Use new Instagram Login (direct Instagram auth)
            "/auth/instagram?vendor_id=#{@vendor.id}"
          when 'youtube'
            "/auth/google_oauth2?vendor_id=#{@vendor.id}&platform=youtube"
          when 'tiktok'
            "/auth/tiktok?vendor_id=#{@vendor.id}"
          when 'whatsapp'
            spree.new_admin_social_media_whatsapp_setup_path
          else
            spree.admin_social_media_path
          end
        end

        def test_account_connection(account)
          case account.platform
          when 'facebook'
            test_facebook_connection(account)
          when 'instagram'
            test_instagram_connection(account)
          when 'youtube'
            test_youtube_connection(account)
          when 'tiktok'
            test_tiktok_connection(account)
          when 'whatsapp'
            test_whatsapp_connection(account)
          else
            { success: false, error: 'Unknown platform' }
          end
        rescue => e
          { success: false, error: e.message }
        end

        def test_facebook_connection(account)
          service = Spree::SocialMedia::FacebookApiService.new(account)
          result = service.test_connection
          { success: result, error: result ? nil : 'Connection failed' }
        end

        def test_instagram_connection(account)
          service = Spree::SocialMedia::InstagramApiService.new(account)
          result = service.test_connection
          { success: result, error: result ? nil : 'Connection failed' }
        end

        def test_youtube_connection(account)
          service = Spree::SocialMedia::YoutubeApiService.new(account)
          result = service.test_connection
          { success: result, error: result ? nil : 'Connection failed' }
        end

        def test_tiktok_connection(account)
          service = Spree::SocialMedia::TiktokApiService.new(account)
          result = service.test_connection
          { success: result, error: result ? nil : 'Connection failed' }
        end

        def test_whatsapp_connection(account)
          service = Spree::SocialMedia::WhatsappApiService.new(account)
          result = service.test_connection
          { success: result, error: result ? nil : 'Connection failed' }
        end
      end
    end
  end
end