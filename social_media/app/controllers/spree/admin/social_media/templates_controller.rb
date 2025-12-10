module Spree
  module Admin
    module SocialMedia
      class TemplatesController < Spree::Admin::ResourceController
        before_action :authenticate_user!
        before_action :load_vendor
        before_action :authorize_social_media_access
        before_action :load_instagram_accounts
        before_action :set_template, only: [:show, :edit, :update, :destroy, :duplicate, :preview, :analytics]

        def index
          @templates = @vendor.social_media_templates
                             .includes(:social_media_account, :social_media_posts)
                             .order(updated_at: :desc)

          # Apply filters
          @templates = @templates.where(template_type: params[:type]) if params[:type].present?
          @templates = @templates.where(content_category: params[:category]) if params[:category].present?
          @templates = @templates.where(active: true) if params[:active] == 'true'

          # Pagination
          @templates = @templates.page(params[:page]).per(12)

          # Load analytics for popular templates
          @popular_templates = @vendor.social_media_templates
                                     .joins(:social_media_posts)
                                     .group('spree_social_media_templates.id')
                                     .order('COUNT(spree_social_media_posts.id) DESC')
                                     .limit(5)
        end

        def show
          @template_analytics = @template.usage_analytics
          @recent_posts = @template.social_media_posts.published.recent.limit(10)
          @suggested_improvements = @template.suggested_improvements
        end

        def new
          @template = @vendor.social_media_templates.build
          @template.template_type = params[:type] || 'post'
          @template.content_category = params[:category] || 'promotional'

          # Pre-fill with sample data if creating from scratch
          if params[:sample] == 'true'
            load_sample_template_data
          end
        end

        def create
          @template = @vendor.social_media_templates.build(template_params)

          if @template.save
            flash[:success] = 'Template created successfully!'
            redirect_to admin_social_media_template_path(@template)
          else
            flash.now[:error] = 'Failed to create template. Please check the form for errors.'
            render :new, status: :unprocessable_entity
          end
        end

        def edit
          # Load template for editing
        end

        def update
          if @template.update(template_params)
            flash[:success] = 'Template updated successfully!'
            redirect_to admin_social_media_template_path(@template)
          else
            flash.now[:error] = 'Failed to update template. Please check the form for errors.'
            render :edit, status: :unprocessable_entity
          end
        end

        def destroy
          if @template.social_media_posts.any?
            flash[:error] = 'Cannot delete template that has been used for posts. Deactivate it instead.'
          elsif @template.destroy
            flash[:success] = 'Template deleted successfully!'
          else
            flash[:error] = 'Failed to delete template.'
          end

          redirect_to admin_social_media_templates_path
        end

        def duplicate
          new_template = @template.duplicate_for_vendor(@vendor)

          if new_template.persisted?
            flash[:success] = 'Template duplicated successfully!'
            redirect_to edit_admin_social_media_template_path(new_template)
          else
            flash[:error] = 'Failed to duplicate template.'
            redirect_to admin_social_media_template_path(@template)
          end
        end

        def preview
          variables = parse_preview_variables(params[:variables])
          rendered = @template.render_template(variables)

          render json: {
            success: true,
            preview: rendered,
            variables_needed: @template.template_variables,
            media_requirements: @template.media_requirements_data
          }
        end

        def analytics
          @analytics = @template.usage_analytics
          @monthly_usage = calculate_monthly_usage
          @performance_comparison = compare_with_other_templates

          respond_to do |format|
            format.html { render :analytics }
            format.json { render json: { analytics: @analytics, monthly_usage: @monthly_usage } }
          end
        end

        def create_from_post
          post = @vendor.social_media_posts.find(params[:post_id])
          @template = Spree::SocialMediaTemplate.create_from_post(post)

          if @template.persisted?
            flash[:success] = 'Template created from post successfully!'
            redirect_to edit_admin_social_media_template_path(@template)
          else
            flash[:error] = 'Failed to create template from post.'
            redirect_back(fallback_location: admin_social_media_posts_path)
          end
        end

        def bulk_actions
          template_ids = params[:template_ids] || []
          action = params[:bulk_action]

          case action
          when 'activate'
            @vendor.social_media_templates.where(id: template_ids).update_all(active: true)
            flash[:success] = "#{template_ids.length} templates activated."
          when 'deactivate'
            @vendor.social_media_templates.where(id: template_ids).update_all(active: false)
            flash[:success] = "#{template_ids.length} templates deactivated."
          when 'delete'
            templates_to_delete = @vendor.social_media_templates.where(id: template_ids)
                                        .left_joins(:social_media_posts)
                                        .where(spree_social_media_posts: { id: nil })

            deleted_count = templates_to_delete.destroy_all.length
            flash[:success] = "#{deleted_count} templates deleted."

            if deleted_count < template_ids.length
              flash[:warning] = "#{template_ids.length - deleted_count} templates could not be deleted (they have been used for posts)."
            end
          end

          redirect_to admin_social_media_templates_path
        end

        def library
          # Public template library - templates shared by other vendors or default templates
          @library_templates = Spree::SocialMediaTemplate
                                 .where(vendor: nil) # System templates
                                 .active
                                 .order(:content_category, :name)

          @categories = @library_templates.group(:content_category).count
        end

        def import_from_library
          library_template = Spree::SocialMediaTemplate.find(params[:template_id])

          @template = library_template.duplicate_for_vendor(@vendor)
          @template.name = "#{library_template.name} (Imported)"

          if @template.save
            flash[:success] = 'Template imported from library successfully!'
            redirect_to edit_admin_social_media_template_path(@template)
          else
            flash[:error] = 'Failed to import template.'
            redirect_to library_admin_social_media_templates_path
          end
        end

        def export
          templates = @vendor.social_media_templates.active

          case params[:format]
          when 'json'
            export_json(templates)
          when 'csv'
            export_csv(templates)
          else
            flash[:error] = 'Unsupported export format'
            redirect_to admin_social_media_templates_path
          end
        end

        def validate_template
          variables = parse_preview_variables(params[:variables])

          validation_results = {
            caption_length: validate_caption_length(params[:caption_template]),
            hashtag_count: validate_hashtag_count(params[:hashtags_template]),
            variable_usage: validate_variables(params[:caption_template], params[:hashtags_template]),
            media_requirements: validate_media_requirements(params[:media_requirements])
          }

          render json: {
            success: true,
            validation: validation_results,
            overall_score: calculate_validation_score(validation_results)
          }
        end

        private

        def authenticate_user!
          unless spree_current_user
            flash[:error] = 'Please sign in to manage templates.'
            redirect_to spree.login_path
          end
        end

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
            flash[:error] = 'No vendor account found.'
            redirect_to spree.admin_path
          end
        end

        def authorize_social_media_access
          authorize! :manage, :social_media_templates
        end

        def load_instagram_accounts
          @instagram_accounts = @vendor.social_media_accounts
                                      .where(platform: 'instagram')
                                      .active
        end

        def set_template
          @template = @vendor.social_media_templates.find(params[:id])
        end

        def template_params
          params.require(:social_media_template).permit(
            :name, :description, :template_type, :content_category,
            :caption_template, :hashtags_template, :instructions,
            :media_requirements_data, :social_media_account_id, :active,
            template_media: []
          )
        end

        def load_sample_template_data
          case @template.template_type
          when 'post'
            @template.caption_template = '🌟 Introducing {{product_name}}! 🌟

Experience the perfect blend of style and functionality with our latest {{product_name}}. Available now for just {{price}}!

✨ Key features:
• Premium quality materials
• {{feature_1}}
• {{feature_2}}

Shop now at {{website}} and use code {{discount_code}} for {{discount}}% off!

#{{brand_name}} #{{product_category}}'
            @template.hashtags_template = '#{{brand_name}} #{{product_category}} #newlaunch #quality #style #shopping #onlineshopping #deals #{{season}}collection'
          when 'story'
            @template.caption_template = '{{product_name}} - now available! ✨
Swipe up to shop 👆
Use code {{discount_code}} for {{discount}}% off'
            @template.hashtags_template = '#{{brand_name}} #{{product_category}} #stories #newdrop'
          when 'reel'
            @template.caption_template = '✨ {{product_name}} in action! ✨

Watch how {{product_name}} transforms your {{use_case}}!

🛒 Get yours today: {{website}}
💸 Save {{discount}}% with code {{discount_code}}

What\'s your favorite feature? Let us know in the comments! 👇'
            @template.hashtags_template = '#{{brand_name}} #{{product_category}} #reels #transformation #tutorial #shopping #deal'
          end

          @template.instructions = "Remember to:\n1. Replace all template variables with actual values\n2. Add high-quality media\n3. Post at optimal times for your audience\n4. Engage with comments within the first hour"
        end

        def parse_preview_variables(variables_param)
          return {} unless variables_param.present?

          if variables_param.is_a?(String)
            begin
              JSON.parse(variables_param)
            rescue JSON::ParserError
              {}
            end
          else
            variables_param.to_h
          end
        end

        def calculate_monthly_usage
          12.times.map do |i|
            month_start = i.months.ago.beginning_of_month
            month_end = i.months.ago.end_of_month

            posts_count = @template.social_media_posts
                                   .where(created_at: month_start..month_end)
                                   .count

            {
              month: month_start.strftime('%b %Y'),
              posts: posts_count
            }
          end.reverse
        end

        def compare_with_other_templates
          other_templates = @vendor.social_media_templates
                                  .where.not(id: @template.id)
                                  .where(template_type: @template.template_type)
                                  .joins(:social_media_posts)
                                  .group('spree_social_media_templates.id')
                                  .select('spree_social_media_templates.*, AVG(spree_social_media_posts.engagement_rate) as avg_engagement')

          {
            current_template_score: @template.usage_analytics[:performance_score] || 0,
            average_score: other_templates.map { |t| t.usage_analytics[:performance_score] || 0 }.sum / [other_templates.length, 1].max,
            rank: calculate_template_rank(other_templates)
          }
        end

        def calculate_template_rank(other_templates)
          current_score = @template.usage_analytics[:performance_score] || 0
          better_templates = other_templates.count { |t| (t.usage_analytics[:performance_score] || 0) > current_score }
          better_templates + 1
        end

        def validate_caption_length(caption)
          return { valid: true, message: 'No caption provided' } unless caption.present?

          length = caption.length
          case length
          when 0..50
            { valid: false, message: 'Caption is too short for optimal engagement', score: 30 }
          when 51..300
            { valid: true, message: 'Good caption length', score: 100 }
          when 301..1000
            { valid: true, message: 'Caption length is good', score: 90 }
          when 1001..2000
            { valid: true, message: 'Long caption - make sure it provides value', score: 70 }
          when 2001..2200
            { valid: false, message: 'Caption is very long, consider shortening', score: 50 }
          else
            { valid: false, message: 'Caption exceeds Instagram limit (2,200 characters)', score: 0 }
          end
        end

        def validate_hashtag_count(hashtags)
          return { valid: true, message: 'No hashtags provided', score: 50 } unless hashtags.present?

          count = hashtags.scan(/#\w+/).length
          case count
          when 0
            { valid: false, message: 'No hashtags found', score: 0 }
          when 1..4
            { valid: false, message: 'Too few hashtags for optimal reach', score: 40 }
          when 5..15
            { valid: true, message: 'Good hashtag count', score: 100 }
          when 16..25
            { valid: true, message: 'High hashtag count - good for reach', score: 90 }
          when 26..30
            { valid: true, message: 'Maximum recommended hashtags', score: 85 }
          else
            { valid: false, message: 'Too many hashtags - may look spammy', score: 30 }
          end
        end

        def validate_variables(caption, hashtags)
          variables_in_caption = caption.to_s.scan(/\{\{([^}]+)\}\}/).flatten
          variables_in_hashtags = hashtags.to_s.scan(/\{\{([^}]+)\}\}/).flatten
          all_variables = (variables_in_caption + variables_in_hashtags).uniq

          {
            valid: true,
            count: all_variables.length,
            variables: all_variables,
            message: all_variables.any? ? "#{all_variables.length} template variables found" : 'No template variables'
          }
        end

        def validate_media_requirements(media_requirements)
          return { valid: true, message: 'No media requirements specified' } unless media_requirements.present?

          begin
            requirements = JSON.parse(media_requirements) if media_requirements.is_a?(String)
            requirements ||= media_requirements

            {
              valid: true,
              requirements: requirements,
              message: 'Media requirements are valid'
            }
          rescue JSON::ParserError
            {
              valid: false,
              message: 'Invalid media requirements format'
            }
          end
        end

        def calculate_validation_score(validation_results)
          scores = []
          scores << validation_results[:caption_length][:score] if validation_results[:caption_length][:score]
          scores << validation_results[:hashtag_count][:score] if validation_results[:hashtag_count][:score]

          scores.any? ? (scores.sum / scores.length).round : 50
        end

        def export_json(templates)
          data = templates.map do |template|
            {
              name: template.name,
              type: template.template_type,
              category: template.content_category,
              caption_template: template.caption_template,
              hashtags_template: template.hashtags_template,
              instructions: template.instructions,
              variables: template.template_variables
            }
          end

          send_data data.to_json,
                    filename: "social_media_templates_#{Date.current}.json",
                    type: 'application/json',
                    disposition: 'attachment'
        end

        def export_csv(templates)
          require 'csv'

          csv_data = CSV.generate do |csv|
            csv << ['Name', 'Type', 'Category', 'Caption Template', 'Hashtags Template', 'Usage Count', 'Last Used', 'Active']

            templates.each do |template|
              csv << [
                template.name,
                template.template_type_display,
                template.content_category_display,
                template.caption_template,
                template.hashtags_template,
                template.usage_count,
                template.last_used_at&.strftime('%Y-%m-%d'),
                template.active? ? 'Yes' : 'No'
              ]
            end
          end

          send_data csv_data,
                    filename: "social_media_templates_#{Date.current}.csv",
                    type: 'text/csv',
                    disposition: 'attachment'
        end
      end
    end
  end
end