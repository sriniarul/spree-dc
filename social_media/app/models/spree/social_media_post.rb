module Spree
  class SocialMediaPost < Spree.base_class
    acts_as_paranoid

    include Spree::Metadata if defined?(Spree::Metadata)

    # Status constants
    STATUSES = %w[draft scheduled posted failed cancelled].freeze
    POST_TYPES = %w[product_post campaign_post manual_post].freeze

    # Associations
    belongs_to :social_media_account, class_name: 'Spree::SocialMediaAccount'
    belongs_to :product, class_name: 'Spree::Product', optional: true
    belongs_to :campaign_post, class_name: 'Spree::CampaignPost', optional: true
    has_many :social_media_analytics, class_name: 'Spree::SocialMediaAnalytics', dependent: :destroy

    # Delegations
    delegate :vendor, :platform, to: :social_media_account
    delegate :name, to: :product, prefix: true, allow_nil: true

    # Validations
    validates :social_media_account_id, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :post_type, presence: true, inclusion: { in: POST_TYPES }
    validates :content, presence: true, length: { maximum: 2200 } # Accommodating different platform limits
    validates :scheduled_at, presence: true, if: :scheduled?
    validates :product_id, presence: true, if: :product_post?

    # Scopes
    scope :draft, -> { where(status: 'draft') }
    scope :scheduled, -> { where(status: 'scheduled') }
    scope :posted, -> { where(status: 'posted') }
    scope :failed, -> { where(status: 'failed') }
    scope :by_platform, ->(platform) { joins(:social_media_account).where(spree_social_media_accounts: { platform: platform }) }
    scope :by_vendor, ->(vendor_id) { joins(:social_media_account).where(spree_social_media_accounts: { vendor_id: vendor_id }) }
    scope :product_posts, -> { where(post_type: 'product_post') }
    scope :campaign_posts, -> { where(post_type: 'campaign_post') }
    scope :ready_to_post, -> { scheduled.where('scheduled_at <= ?', Time.current) }
    scope :recent, -> { order(created_at: :desc) }

    # Callbacks
    before_validation :set_default_status, on: :create
    after_create :schedule_posting_job, if: :scheduled?
    after_update :reschedule_posting_job, if: :saved_change_to_scheduled_at?

    # Status methods
    def draft?
      status == 'draft'
    end

    def scheduled?
      status == 'scheduled'
    end

    def posted?
      status == 'posted'
    end

    def failed?
      status == 'failed'
    end

    def cancelled?
      status == 'cancelled'
    end

    def product_post?
      post_type == 'product_post'
    end

    def campaign_post?
      post_type == 'campaign_post'
    end

    def manual_post?
      post_type == 'manual_post'
    end

    # State transition methods
    def schedule!(scheduled_time)
      return false if posted?

      transaction do
        update!(
          status: 'scheduled',
          scheduled_at: scheduled_time
        )
        schedule_posting_job
      end
    end

    def post_now!
      return false if posted?

      Spree::SocialMedia::PostToSocialMediaJob.perform_now(id)
    end

    def mark_posted!(platform_post_id, platform_url = nil)
      update!(
        status: 'posted',
        platform_post_id: platform_post_id,
        platform_url: platform_url,
        posted_at: Time.current
      )
    end

    def mark_failed!(error_message)
      update!(
        status: 'failed',
        error_message: error_message,
        failed_at: Time.current
      )
    end

    def cancel!
      return false if posted?

      update!(status: 'cancelled')
      cancel_posting_job
    end

    # Content generation methods
    def generate_content_from_template(template = nil)
      return unless product

      template ||= default_template_for_platform

      content = template.dup
      content.gsub!('{{product_name}}', product.name)
      content.gsub!('{{product_description}}', product.description.to_s.truncate(100))
      content.gsub!('{{product_price}}', product.price.to_s)
      content.gsub!('{{product_url}}', product_url)
      content.gsub!('{{store_name}}', vendor.name)
      content.gsub!('{{vendor_name}}', vendor.display_name)

      self.content = content
    end

    def product_url
      return unless product

      # This would generate the proper product URL for the storefront
      Rails.application.routes.url_helpers.spree_product_url(product, host: default_host)
    end

    # Platform-specific content optimization
    def optimize_content_for_platform
      case platform
      when 'twitter'
        self.content = content.truncate(280) if content.length > 280
      when 'instagram'
        self.content = content.truncate(2200) if content.length > 2200
      when 'facebook'
        self.content = content.truncate(1000) if content.length > 1000
      when 'tiktok'
        self.content = content.truncate(150) if content.length > 150
      end
    end

    # Analytics methods
    def performance_metrics
      analytics = social_media_analytics.sum_by_metric

      {
        impressions: analytics['impressions'] || 0,
        likes: analytics['likes'] || 0,
        comments: analytics['comments'] || 0,
        shares: analytics['shares'] || 0,
        clicks: analytics['clicks'] || 0,
        engagement_rate: calculate_engagement_rate(analytics)
      }
    end

    def latest_analytics
      social_media_analytics.order(date: :desc).first
    end

    private

    def set_default_status
      self.status ||= 'draft'
      self.post_type ||= determine_post_type
    end

    def determine_post_type
      if campaign_post_id.present?
        'campaign_post'
      elsif product_id.present?
        'product_post'
      else
        'manual_post'
      end
    end

    def default_template_for_platform
      case platform
      when 'instagram'
        '✨ {{product_name}} ✨

{{product_description}}

💰 Price: {{product_price}}
🛒 Shop now: {{product_url}}

#{{store_name}} #shopping #ecommerce'
      when 'facebook'
        'Check out this amazing product: {{product_name}}

{{product_description}}

Price: {{product_price}}

Shop now: {{product_url}}'
      when 'youtube'
        '{{product_name}} - Available at {{store_name}}

{{product_description}}

Get yours today: {{product_url}}'
      when 'tiktok'
        '{{product_name}} 🔥
{{product_price}} only!
{{product_url}}
#{{store_name}} #fyp #shopping'
      else
        SpreeSocialMedia::Config.default_post_template
      end
    end

    def default_host
      # This should be configured based on your application's domain
      Rails.application.config.action_mailer.default_url_options[:host] || 'localhost:3000'
    end

    def schedule_posting_job
      return unless scheduled? && scheduled_at.present?
      return if scheduled_at <= Time.current # Don't schedule if time is in the past

      # Use ActiveJob's set method to schedule the job
      # This works with any ActiveJob backend (Sidekiq, DelayedJob, etc.)
      Spree::SocialMedia::PostToSocialMediaJob.set(wait_until: scheduled_at).perform_later(id)

      Rails.logger.info "Scheduled post #{id} for #{scheduled_at}"
    end

    def reschedule_posting_job
      return unless scheduled?

      # Cancel previous schedule (if supported by job backend)
      cancel_posting_job

      # Schedule new job
      schedule_posting_job
    end

    def cancel_posting_job
      # Note: Canceling scheduled jobs depends on your job queue backend
      # Sidekiq Pro supports this, but basic Sidekiq/ActiveJob doesn't
      # For now, we'll just log it
      Rails.logger.info "Cancel requested for scheduled post #{id}"

      # If using Sidekiq Pro, you could implement this:
      # Sidekiq::ScheduledSet.new.each do |job|
      #   if job.args[0] == id && job.klass == 'Spree::SocialMedia::PostToSocialMediaJob'
      #     job.delete
      #   end
      # end
    end

    def calculate_engagement_rate(analytics)
      impressions = analytics['impressions']&.to_i || 0
      return 0 if impressions.zero?

      engagements = (analytics['likes']&.to_i || 0) +
                   (analytics['comments']&.to_i || 0) +
                   (analytics['shares']&.to_i || 0)

      ((engagements.to_f / impressions) * 100).round(2)
    end
  end
end