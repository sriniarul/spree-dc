module Spree
  module Admin
    module SocialMedia
      class ComplianceController < Spree::Admin::BaseController
        before_action :load_account, only: [:show, :check_compliance, :update_settings]
        before_action :load_vendor_accounts, only: [:index]

        def index
          @compliance_overview = calculate_compliance_overview
          @recent_violations = load_recent_violations
          @compliance_trends = calculate_compliance_trends
        end

        def show
          @compliance_status = check_account_compliance
          @moderation_history = load_moderation_history
          @compliance_settings = load_compliance_settings
        end

        def check_compliance
          service = Spree::SocialMedia::ContentModerationService.new(@account)
          @compliance_results = service.check_compliance_status

          respond_to do |format|
            format.html { redirect_to admin_social_media_compliance_path(@account), notice: 'Compliance check completed.' }
            format.json { render json: @compliance_results }
          end
        end

        def update_settings
          compliance_params = params.require(:compliance_settings).permit(
            :auto_moderation_enabled,
            :moderation_level,
            :require_approval_for_high_risk,
            :enable_hashtag_filtering,
            :enable_content_scanning,
            brand_guidelines: [
              :voice_tone,
              :restricted_topics,
              { restricted_keywords: [] },
              { approved_hashtags: [] },
              { banned_hashtags: [] }
            ],
            notification_settings: [
              :notify_on_violations,
              :notify_on_high_risk_content,
              :daily_compliance_report
            ]
          )

          @account.vendor.update!(compliance_settings: compliance_params.to_h)

          redirect_to admin_social_media_compliance_path(@account),
                      notice: 'Compliance settings updated successfully.'
        end

        def moderation_queue
          @pending_content = load_pending_moderation_content
          @flagged_comments = load_flagged_comments
          @policy_violations = load_policy_violations
        end

        def moderate_content
          content_id = params[:content_id]
          action = params[:action_type] # approve, reject, request_changes
          notes = params[:moderation_notes]

          case params[:content_type]
          when 'post'
            moderate_post_content(content_id, action, notes)
          when 'comment'
            moderate_comment_content(content_id, action, notes)
          end

          redirect_to admin_social_media_compliance_moderation_queue_path,
                      notice: 'Content moderation action completed.'
        end

        def compliance_report
          @report_data = generate_compliance_report(
            start_date: params[:start_date]&.to_date || 30.days.ago.to_date,
            end_date: params[:end_date]&.to_date || Date.current,
            account_ids: params[:account_ids]
          )

          respond_to do |format|
            format.html
            format.pdf { render_compliance_pdf }
            format.csv { render_compliance_csv }
          end
        end

        def violation_details
          @violation = load_violation_details(params[:violation_id])
          @related_content = load_related_content(@violation)
          @remediation_actions = suggest_remediation_actions(@violation)

          respond_to do |format|
            format.html
            format.json { render json: { violation: @violation, actions: @remediation_actions } }
          end
        end

        def bulk_moderate
          content_ids = params[:content_ids].split(',')
          action = params[:bulk_action]
          notes = params[:bulk_notes]

          results = {
            success: 0,
            failed: 0,
            errors: []
          }

          content_ids.each do |content_id|
            begin
              case params[:content_type]
              when 'post'
                moderate_post_content(content_id, action, notes)
              when 'comment'
                moderate_comment_content(content_id, action, notes)
              end
              results[:success] += 1
            rescue => e
              results[:failed] += 1
              results[:errors] << { content_id: content_id, error: e.message }
            end
          end

          render json: results
        end

        private

        def load_account
          @account = current_vendor.social_media_accounts.find(params[:account_id])
        rescue ActiveRecord::RecordNotFound
          redirect_to admin_social_media_accounts_path, alert: 'Account not found.'
        end

        def load_vendor_accounts
          @accounts = current_vendor.social_media_accounts.active
        end

        def calculate_compliance_overview
          accounts = current_vendor.social_media_accounts.active

          overview = {
            total_accounts: accounts.count,
            compliant_accounts: 0,
            at_risk_accounts: 0,
            non_compliant_accounts: 0,
            total_violations: 0,
            recent_violations: 0
          }

          accounts.each do |account|
            service = Spree::SocialMedia::ContentModerationService.new(account)
            status = service.check_compliance_status

            case status[:overall_status]
            when 'compliant'
              overview[:compliant_accounts] += 1
            when 'at_risk', 'minor_issues'
              overview[:at_risk_accounts] += 1
            when 'non_compliant'
              overview[:non_compliant_accounts] += 1
            end

            overview[:total_violations] += status[:issues].count
            overview[:recent_violations] += status[:issues].count { |issue|
              issue[:created_at] && issue[:created_at] > 7.days.ago
            }
          end

          overview
        end

        def load_recent_violations
          # Load recent violations across all vendor accounts
          Spree::ContentViolation
            .joins(social_media_post: :social_media_account)
            .where(spree_social_media_accounts: { vendor: current_vendor })
            .where('created_at > ?', 7.days.ago)
            .order(created_at: :desc)
            .limit(20)
        rescue
          [] # Return empty array if violations table doesn't exist yet
        end

        def calculate_compliance_trends
          # Calculate compliance trends over the last 30 days
          end_date = Date.current
          start_date = end_date - 29.days

          trends = {}
          (start_date..end_date).each do |date|
            trends[date] = {
              violations: 0,
              compliance_score: 100
            }
          end

          # This would be populated with actual violation data
          trends
        end

        def check_account_compliance
          service = Spree::SocialMedia::ContentModerationService.new(@account)
          service.check_compliance_status
        end

        def load_moderation_history
          # Load recent moderation actions for this account
          @account.social_media_posts
                  .includes(:moderation_actions)
                  .where('created_at > ?', 30.days.ago)
                  .order(created_at: :desc)
                  .limit(50)
        rescue
          []
        end

        def load_compliance_settings
          @account.vendor.compliance_settings || {
            auto_moderation_enabled: true,
            moderation_level: 'medium',
            require_approval_for_high_risk: true,
            enable_hashtag_filtering: true,
            enable_content_scanning: true
          }
        end

        def load_pending_moderation_content
          # Load content pending moderation approval
          current_vendor.social_media_accounts
                        .joins(:social_media_posts)
                        .where(spree_social_media_posts: {
                          status: 'pending_moderation',
                          created_at: 1.week.ago..Time.current
                        })
                        .order('spree_social_media_posts.created_at DESC')
                        .limit(50)
        rescue
          []
        end

        def load_flagged_comments
          # Load comments that have been flagged for review
          Spree::SocialMediaComment
            .joins(:social_media_account)
            .where(spree_social_media_accounts: { vendor: current_vendor })
            .where(flagged_for_review: true)
            .where('created_at > ?', 1.week.ago)
            .order(created_at: :desc)
            .limit(30)
        rescue
          []
        end

        def load_policy_violations
          # Load recent policy violations
          Spree::PolicyViolation
            .joins(social_media_account: :vendor)
            .where(vendors: { id: current_vendor.id })
            .where('created_at > ?', 1.week.ago)
            .order(severity: :desc, created_at: :desc)
            .limit(20)
        rescue
          []
        end

        def moderate_post_content(post_id, action, notes)
          post = Spree::SocialMediaPost.find(post_id)

          case action
          when 'approve'
            post.update!(status: 'approved', moderation_notes: notes)
            # Queue for publishing if scheduled
            if post.scheduled_for.present? && post.scheduled_for > Time.current
              Spree::SocialMedia::PublishPostJob.perform_at(post.scheduled_for, post.id)
            end
          when 'reject'
            post.update!(status: 'rejected', moderation_notes: notes)
          when 'request_changes'
            post.update!(status: 'requires_changes', moderation_notes: notes)
            # Notify vendor about required changes
            send_moderation_notification(post, 'changes_requested', notes)
          end

          # Log moderation action
          create_moderation_log(post, action, notes)
        end

        def moderate_comment_content(comment_id, action, notes)
          comment = Spree::SocialMediaComment.find(comment_id)

          case action
          when 'approve'
            comment.update!(moderation_status: 'approved', moderation_notes: notes)
          when 'reject'
            comment.update!(moderation_status: 'rejected', moderation_notes: notes)
            # Hide or remove comment if it was already published
            hide_comment_if_published(comment)
          when 'flag'
            comment.update!(flagged_for_review: true, moderation_notes: notes)
          end

          create_moderation_log(comment, action, notes)
        end

        def generate_compliance_report(start_date:, end_date:, account_ids: nil)
          accounts = current_vendor.social_media_accounts.active
          accounts = accounts.where(id: account_ids) if account_ids.present?

          report_data = {
            period: { start_date: start_date, end_date: end_date },
            accounts: [],
            summary: {
              total_violations: 0,
              violation_types: {},
              compliance_score: 0
            }
          }

          accounts.each do |account|
            service = Spree::SocialMedia::ContentModerationService.new(account)
            account_status = service.check_compliance_status

            account_data = {
              account_name: account.username,
              platform: account.platform,
              status: account_status[:overall_status],
              violations: account_status[:issues].count,
              last_check: account_status[:last_check]
            }

            report_data[:accounts] << account_data
            report_data[:summary][:total_violations] += account_data[:violations]
          end

          # Calculate overall compliance score
          total_possible_score = accounts.count * 100
          violation_penalty = report_data[:summary][:total_violations] * 10
          report_data[:summary][:compliance_score] = [
            ((total_possible_score - violation_penalty).to_f / total_possible_score * 100).round(1),
            0
          ].max

          report_data
        end

        def render_compliance_pdf
          # This would generate a PDF compliance report
          # For now, redirect to HTML view
          redirect_to admin_social_media_compliance_compliance_report_path(format: :html)
        end

        def render_compliance_csv
          # This would generate a CSV compliance report
          csv_data = generate_compliance_csv(@report_data)
          send_data csv_data, filename: "compliance_report_#{Date.current}.csv", type: 'text/csv'
        end

        def generate_compliance_csv(report_data)
          CSV.generate do |csv|
            csv << ['Account', 'Platform', 'Status', 'Violations', 'Last Check']

            report_data[:accounts].each do |account|
              csv << [
                account[:account_name],
                account[:platform],
                account[:status],
                account[:violations],
                account[:last_check]
              ]
            end
          end
        end

        def load_violation_details(violation_id)
          # Load detailed information about a specific violation
          {
            id: violation_id,
            type: 'inappropriate_content',
            severity: 'medium',
            description: 'Content flagged for potential policy violation',
            created_at: 1.day.ago,
            status: 'under_review'
          }
        end

        def load_related_content(violation)
          # Load content related to the violation
          []
        end

        def suggest_remediation_actions(violation)
          # Suggest actions to address the violation
          [
            { action: 'Edit content to remove inappropriate language', priority: 'high' },
            { action: 'Add content warning or disclaimer', priority: 'medium' },
            { action: 'Remove content if unable to modify', priority: 'low' }
          ]
        end

        def send_moderation_notification(content, notification_type, notes)
          # Send notification to vendor about moderation action
          Rails.logger.info "Sending moderation notification: #{notification_type} for #{content.class.name} #{content.id}"
        end

        def create_moderation_log(content, action, notes)
          # Create log entry for moderation action
          Rails.logger.info "Moderation action logged: #{action} on #{content.class.name} #{content.id}"
        end

        def hide_comment_if_published(comment)
          # Hide comment on the platform if it was already published
          Rails.logger.info "Hiding published comment #{comment.id}"
        end

        def current_vendor
          @current_vendor ||= current_spree_user&.vendors&.first ||
                             Spree::Vendor.find(params[:vendor_id]) if params[:vendor_id]
        end
      end
    end
  end
end