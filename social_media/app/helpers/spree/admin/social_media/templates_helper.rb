module Spree
  module Admin
    module SocialMedia
      module TemplatesHelper
        def template_type_color(template_type)
          case template_type
          when 'post'
            'primary'
          when 'story'
            'success'
          when 'reel'
            'info'
          when 'carousel'
            'warning'
          else
            'secondary'
          end
        end

        def template_category_icon(category)
          case category
          when 'product_showcase'
            'fa-shopping-bag'
          when 'promotional'
            'fa-percent'
          when 'educational'
            'fa-graduation-cap'
          when 'behind_the_scenes'
            'fa-camera'
          when 'user_generated_content'
            'fa-users'
          when 'seasonal_holiday'
            'fa-calendar'
          when 'announcement'
            'fa-bullhorn'
          when 'testimonial_review'
            'fa-star'
          when 'how_to_tutorial'
            'fa-play-circle'
          when 'brand_story'
            'fa-book'
          when 'event_coverage'
            'fa-calendar-check'
          when 'quote_inspiration'
            'fa-quote-left'
          when 'industry_news'
            'fa-newspaper'
          when 'community_engagement'
            'fa-comments'
          else
            'fa-file'
          end
        end

        def render_template_variables_form(template_variables)
          return '' if template_variables.blank?

          content_tag :div, class: 'template-variables-form' do
            template_variables.map do |variable|
              content_tag :div, class: 'mb-3' do
                label = content_tag :label, "#{variable.humanize}:", class: 'form-label'
                input = text_field_tag "variables[#{variable}]", '',
                                     class: 'form-control',
                                     placeholder: "Enter #{variable.humanize.downcase}"

                label + input
              end
            end.join.html_safe
          end
        end

        def template_performance_badge(template)
          analytics = template.usage_analytics
          return content_tag(:span, 'No Data', class: 'badge bg-secondary') if analytics.empty?

          engagement_rate = analytics[:avg_engagement_rate] || 0

          badge_class = case engagement_rate
                       when 0...1
                         'bg-danger'
                       when 1...3
                         'bg-warning'
                       when 3...5
                         'bg-success'
                       else
                         'bg-primary'
                       end

          content_tag :span, "#{engagement_rate}% avg", class: "badge #{badge_class}"
        end

        def template_usage_trend(template, period = 6)
          return [] unless template.persisted?

          period.times.map do |i|
            month_start = i.months.ago.beginning_of_month
            month_end = i.months.ago.end_of_month

            usage_count = template.social_media_posts
                                 .where(created_at: month_start..month_end)
                                 .count

            {
              month: month_start.strftime('%b'),
              count: usage_count
            }
          end.reverse
        end

        def render_template_preview(template, variables = {})
          rendered = template.render_template(variables)

          content_tag :div, class: 'template-preview' do
            caption_preview = content_tag :div, class: 'caption-preview mb-3' do
              content_tag(:h6, 'Caption:') +
              content_tag(:div, simple_format(rendered[:caption]), class: 'border rounded p-3 bg-light')
            end

            hashtags_preview = content_tag :div, class: 'hashtags-preview' do
              content_tag(:h6, 'Hashtags:') +
              content_tag(:div, rendered[:hashtags], class: 'border rounded p-3 bg-light')
            end

            caption_preview + hashtags_preview
          end
        end

        def template_validation_status(template)
          suggestions = template.suggested_improvements

          if suggestions.empty?
            content_tag :span, 'Valid', class: 'badge bg-success'
          elsif suggestions.length <= 2
            content_tag :span, 'Minor Issues', class: 'badge bg-warning'
          else
            content_tag :span, 'Needs Review', class: 'badge bg-danger'
          end
        end

        def format_template_variables(variables)
          return 'None' if variables.blank?

          variables.map do |var|
            content_tag :span, var, class: 'badge bg-light text-dark me-1'
          end.join.html_safe
        end

        def template_type_options_for_select
          Spree::SocialMediaTemplate::TEMPLATE_TYPES.map { |key, label| [label, key] }
        end

        def content_category_options_for_select
          Spree::SocialMediaTemplate.content_category_options
        end

        def media_requirements_summary(template)
          return 'None specified' unless template.media_requirements_data.present?

          begin
            requirements = JSON.parse(template.media_requirements_data)

            summary_parts = []
            summary_parts << "#{requirements['min_count']}-#{requirements['max_count']} files" if requirements['min_count'] || requirements['max_count']
            summary_parts << "Types: #{requirements['allowed_types'].join(', ')}" if requirements['allowed_types']
            summary_parts << "Aspect ratios: #{requirements['aspect_ratios'].map(&:to_s).join(', ')}" if requirements['aspect_ratios']

            summary_parts.any? ? summary_parts.join(', ') : 'Custom requirements'
          rescue JSON::ParserError
            'Invalid format'
          end
        end

        def template_stats_chart_data(template)
          usage_data = template_usage_trend(template, 12)

          {
            labels: usage_data.map { |d| d[:month] },
            data: usage_data.map { |d| d[:count] }
          }.to_json
        end

        def recent_template_activity(vendor, limit = 5)
          vendor.social_media_templates
                .joins(:social_media_posts)
                .where('spree_social_media_posts.created_at > ?', 30.days.ago)
                .group('spree_social_media_templates.id')
                .order('COUNT(spree_social_media_posts.id) DESC')
                .limit(limit)
                .includes(:social_media_posts)
        end

        def template_export_options
          [
            ['JSON Format', 'json'],
            ['CSV Format', 'csv']
          ]
        end

        def render_media_requirements_preview(requirements_json)
          return content_tag(:em, 'No requirements specified', class: 'text-muted') unless requirements_json.present?

          begin
            requirements = JSON.parse(requirements_json)

            content_tag :ul, class: 'list-unstyled mb-0' do
              items = []

              if requirements['min_count'] || requirements['max_count']
                min_count = requirements['min_count'] || 0
                max_count = requirements['max_count'] || '∞'
                items << content_tag(:li, "Files: #{min_count} - #{max_count}")
              end

              if requirements['allowed_types']
                items << content_tag(:li, "Types: #{requirements['allowed_types'].join(', ')}")
              end

              if requirements['aspect_ratios']
                ratios = requirements['aspect_ratios'].map { |r| "#{r}:1" }.join(', ')
                items << content_tag(:li, "Aspect ratios: #{ratios}")
              end

              items.join.html_safe
            end
          rescue JSON::ParserError
            content_tag :em, 'Invalid requirements format', class: 'text-danger'
          end
        end
      end
    end
  end
end