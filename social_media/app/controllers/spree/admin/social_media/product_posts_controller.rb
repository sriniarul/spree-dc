module Spree
  module Admin
    module SocialMedia
      class ProductPostsController < Spree::Admin::BaseController
        before_action :load_product, only: [:new, :create]
        before_action :load_products, only: [:bulk_new, :bulk_create]
        before_action :load_social_media_accounts, only: [:new, :bulk_new]
        before_action :authorize_social_media_posts

        def new
          @post = Spree::SocialMediaPost.new
          @post.product = @product

          # Auto-generate caption from product data
          @suggested_caption = generate_caption_for_product(@product)
        end

        def create
          @post = Spree::SocialMediaPost.new(post_params)
          @post.product = @product
          # Vendor is already set through social_media_account relationship

          if params[:publish_now] == 'true'
            if @post.save && publish_post(@post)
              flash[:success] = "Post published successfully to #{@post.social_media_account.platform.humanize}!"
              redirect_to spree.admin_product_path(@product)
            else
              flash.now[:error] = @post.errors.full_messages.join(', ')
              load_social_media_accounts
              render :new
            end
          else
            @post.status = 'scheduled'
            if @post.save
              flash[:success] = "Post scheduled successfully for #{@post.scheduled_at.strftime('%B %d, %Y at %I:%M %p')}"
              redirect_to spree.admin_product_path(@product)
            else
              flash.now[:error] = @post.errors.full_messages.join(', ')
              load_social_media_accounts
              render :new
            end
          end
        end

        def bulk_new
          @posts = @products.map do |product|
            post = Spree::SocialMediaPost.new
            post.product = product
            post.content = generate_caption_for_product(product)
            post
          end
        end

        def bulk_create
          results = { success: [], failed: [] }

          @products.each_with_index do |product, index|
            post = Spree::SocialMediaPost.new(bulk_post_params(index))
            post.product = product

            # Auto-generate caption if using auto mode or if content is blank
            if params[:caption_mode] == 'auto' || post.content.blank?
              post.content = generate_caption_for_product(product)
            end

            # Vendor is already set through social_media_account relationship

            if params[:publish_now] == 'true'
              if post.save && publish_post(post)
                results[:success] << product.name
              else
                results[:failed] << "#{product.name}: #{post.errors.full_messages.join(', ')}"
              end
            else
              post.status = 'scheduled'
              if post.save
                results[:success] << product.name
              else
                results[:failed] << "#{product.name}: #{post.errors.full_messages.join(', ')}"
              end
            end
          end

          flash[:success] = "Successfully posted #{results[:success].count} products" if results[:success].any?
          flash[:error] = "Failed to post: #{results[:failed].join('; ')}" if results[:failed].any?

          redirect_to spree.admin_products_path
        end

        private

        def authorize_social_media_posts
          authorize! :create, Spree::Product
        end

        def current_vendor
          @current_vendor ||= if respond_to?(:spree_current_user) && spree_current_user&.vendor
                                spree_current_user.vendor
                              else
                                try_spree_current_user&.vendor || Spree::Vendor.first
                              end
        end

        def load_product
          @product = Spree::Product.friendly.find(params[:product_id])
        end

        def load_products
          # Handle both comma-separated string and array formats
          product_ids = params[:product_ids] || params[:products] || []

          # If it's a string, split by comma
          if product_ids.is_a?(String)
            product_ids = product_ids.split(',').map(&:strip)
          end

          @products = Spree::Product.where(id: product_ids)

          if @products.empty?
            flash[:error] = "Please select at least one product"
            redirect_to spree.admin_products_path and return
          end
        end

        def load_social_media_accounts
          @social_media_accounts = Spree::SocialMediaAccount.where(status: 'active')

          if current_vendor
            @social_media_accounts = @social_media_accounts.where(vendor: current_vendor)
          end

          if @social_media_accounts.empty?
            flash[:warning] = "Please connect a social media account first"
            redirect_to spree.admin_social_media_accounts_path
          end
        end

        def post_params
          params_hash = {
            social_media_account_id: params[:social_media_account_id],
            content: params[:content] || params[:caption], # Support both parameter names
            hashtags: params[:hashtags],
            scheduled_at: params[:scheduled_at],
            post_type: 'product_post'
          }

          # Store content_type in post_options if provided
          if params[:content_type].present?
            params_hash[:post_options] = { content_type: params[:content_type] }
          end

          params_hash
        end

        def bulk_post_params(index)
          params_hash = {
            social_media_account_id: params[:social_media_account_id],
            content: params[:contents]&.dig(index.to_s) || params[:captions]&.dig(index.to_s), # Support both parameter names
            hashtags: params[:hashtags],
            scheduled_at: params[:scheduled_at],
            post_type: 'product_post'
          }

          # Store content_type in post_options if provided
          if params[:content_type].present?
            params_hash[:post_options] = { content_type: params[:content_type] }
          end

          params_hash
        end

        def generate_caption_for_product(product)
          caption_parts = []

          # Product name
          caption_parts << product.name

          # Description (first 100 chars)
          if product.description.present?
            desc = ActionView::Base.full_sanitizer.sanitize(product.description)
            caption_parts << desc.truncate(100)
          end

          # Price with currency
          if product.price
            caption_parts << "Price: #{product.display_price}"
          end

          # Call to action
          caption_parts << "\n\nShop now! Link in bio."

          caption_parts.join("\n\n")
        end

        def publish_post(post)
          account = post.social_media_account

          # Get media URLs from selected images or all product images
          media_urls = get_media_urls_for_post(post)

          api_service = case account.platform
          when 'instagram'
            Spree::SocialMedia::InstagramApiService.new(account)
          when 'facebook'
            Spree::SocialMedia::FacebookApiService.new(account)
          else
            return false
          end

          result = api_service.post(post.content, {
            content_type: post.post_options&.dig('content_type') || 'feed',
            media_urls: media_urls,
            hashtags: post.hashtags
          })

          if result[:success]
            post.update(
              status: 'posted',
              platform_post_id: result[:platform_post_id],
              platform_url: result[:platform_url],
              posted_at: Time.current
            )
            true
          else
            post.errors.add(:base, result[:error])
            false
          end
        end

        def get_media_urls_for_post(post)
          # Check if specific images were selected
          selected_image_ids = params[:selected_image_ids]

          if selected_image_ids.present?
            # Use selected images in the specified order
            image_ids = selected_image_ids.split(',').map(&:strip)

            # Get images maintaining the order
            ordered_images = image_ids.map do |image_id|
              post.product.images.find { |img| img.id.to_s == image_id }
            end.compact

            # Generate URLs for selected images
            ordered_images.map do |image|
              generate_public_media_url(image)
            end
          else
            # Use all product images (default behavior)
            post.product.images.first(10).map do |image|
              generate_public_media_url(image)
            end
          end
        end

        def generate_public_media_url(image)
          # Use the request host (ngrok/actual domain) instead of store URL (which might be localhost)
          # Instagram's servers need to access these URLs, so localhost won't work
          host = request.host_with_port

          # rails_storage_proxy_url generates direct URLs through Active Storage proxy
          # This is publicly accessible and doesn't require authentication
          Rails.application.routes.url_helpers.rails_storage_proxy_url(
            image.attachment.blob,
            host: host,
            protocol: 'https'
          )
        end
      end
    end
  end
end
