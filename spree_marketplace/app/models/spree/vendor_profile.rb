# frozen_string_literal: true

module Spree
  class VendorProfile < Spree.base_class
    # Core Spree patterns
    include Spree::Metadata
    auto_strip_attributes :business_name, :tax_id, :business_license_number
    
    # Associations following Spree patterns
    belongs_to :vendor, inverse_of: :vendor_profile
    
    # File attachments for vendor verification
    has_many_attached :business_documents
    has_many_attached :tax_documents
    has_many_attached :identity_documents
    has_many_attached :bank_documents
    
    # Business type enumeration
    enum business_type: {
      individual: 0,
      sole_proprietorship: 1,
      partnership: 2,
      llc: 3,
      corporation: 4,
      s_corporation: 5,
      non_profit: 6,
      other: 99
    }, _prefix: true
    
    # Verification status
    enum verification_status: {
      unverified: 0,
      pending_verification: 1,
      partially_verified: 2,
      verified: 3,
      rejected: 4,
      requires_update: 5
    }, _prefix: true
    
    # Payout schedule
    enum payout_schedule: {
      weekly: 0,
      biweekly: 1,
      monthly: 2,
      quarterly: 3,
      manual: 4
    }, _prefix: true
    
    # Validations following Spree patterns
    validates :business_name, presence: true, length: { maximum: 255 }
    validates :tax_id, presence: true, 
                       uniqueness: { scope: spree_base_uniqueness_scope },
                       length: { maximum: 50 }
    validates :commission_rate, presence: true, 
                                numericality: { 
                                  greater_than: 0, 
                                  less_than_or_equal_to: 1 
                                }
    validates :business_type, presence: true
    validates :verification_status, presence: true
    validates :payout_schedule, presence: true
    
    # Conditional validations based on configuration
    validates :business_license_number, presence: true,
              if: -> { SpreeMarketplace.configuration.require_business_verification }
    
    validates :bank_account_details, presence: true,
              if: -> { SpreeMarketplace.configuration.require_bank_details }
    
    # JSON store accessors for business address
    store_accessor :business_address, 
                   :street, :street2, :city, :state, :country, :zipcode, :phone
    
    # JSON store accessors for tax settings
    store_accessor :tax_settings,
                   :tax_exempt, :tax_id_type, :vat_number, :tax_classification
                   
    # JSON store accessors for bank details (encrypted)
    encrypts :bank_account_details
    store_accessor :bank_account_details,
                   :account_type, :routing_number, :account_number, 
                   :bank_name, :account_holder_name
    
    # JSON store accessors for business details
    store_accessor :business_details,
                   :established_year, :employee_count, :annual_revenue,
                   :business_description, :website_url, :social_media
    
    # Validation callbacks
    before_validation :set_defaults
    before_validation :normalize_tax_id
    before_validation :validate_business_address
    before_validation :validate_commission_rate_bounds
    
    # File attachment validations
    validate :validate_document_attachments
    validate :validate_document_sizes
    validate :validate_document_types
    
    # Scopes for admin filtering
    scope :verified, -> { where(verification_status: :verified) }
    scope :pending_verification, -> { where(verification_status: :pending_verification) }
    scope :rejected, -> { where(verification_status: :rejected) }
    scope :by_business_type, ->(type) { where(business_type: type) }
    scope :high_commission, -> { where('commission_rate > ?', 0.20) }
    
    # Ransack configuration
    def self.ransackable_attributes(auth_object = nil)
      %w[business_name tax_id business_type verification_status commission_rate 
         payout_schedule created_at updated_at]
    end
    
    # Business logic methods
    def complete_address
      return nil unless business_address_complete?
      
      [street, street2, city, state, zipcode, country].compact.join(', ')
    end
    
    def business_address_complete?
      street.present? && city.present? && state.present? && 
      country.present? && zipcode.present?
    end
    
    def verification_complete?
      return false unless verification_status_verified?
      
      required_documents_uploaded? && 
      business_address_complete? && 
      bank_details_complete?
    end
    
    def required_documents_uploaded?
      business_documents.any? && 
      tax_documents.any? && 
      identity_documents.any?
    end
    
    def bank_details_complete?
      return true unless SpreeMarketplace.configuration.require_bank_details
      
      bank_account_details.present? &&
      bank_account_details['account_number'].present? &&
      bank_account_details['routing_number'].present? &&
      bank_account_details['bank_name'].present?
    end
    
    def tax_exempt?
      tax_settings.present? && tax_settings['tax_exempt'] == 'true'
    end
    
    def commission_percentage
      (commission_rate * 100).to_i if commission_rate.present?
    end
    
    def next_payout_date
      case payout_schedule
      when 'weekly'
        1.week.from_now.end_of_week
      when 'biweekly'
        2.weeks.from_now.end_of_week
      when 'monthly'
        1.month.from_now.end_of_month
      when 'quarterly'
        3.months.from_now.end_of_quarter
      else
        nil # Manual payouts
      end
    end
    
    def business_age_years
      return nil unless business_details['established_year'].present?
      
      Date.current.year - business_details['established_year'].to_i
    end
    
    # Document management helpers
    def primary_business_document
      business_documents.first
    end
    
    def primary_tax_document
      tax_documents.first
    end
    
    def primary_identity_document
      identity_documents.first
    end
    
    # Verification workflow methods
    def submit_for_verification!
      return false unless can_submit_for_verification?
      
      update!(
        verification_status: :pending_verification,
        verification_submitted_at: Time.current
      )
      
      VendorMailer.verification_submitted(vendor).deliver_later
      AdminMailer.vendor_verification_pending(vendor).deliver_later
      
      true
    end
    
    def approve_verification!(admin_user = nil)
      update!(
        verification_status: :verified,
        verification_approved_at: Time.current,
        verification_approved_by: admin_user
      )
      
      vendor.activate! if vendor.pending?
      VendorMailer.verification_approved(vendor).deliver_later
    end
    
    def reject_verification!(reason, admin_user = nil)
      update!(
        verification_status: :rejected,
        verification_rejected_at: Time.current,
        verification_rejected_by: admin_user,
        verification_rejection_reason: reason
      )
      
      vendor.reject! unless vendor.blocked?
      VendorMailer.verification_rejected(vendor, reason).deliver_later
    end
    
    def can_submit_for_verification?
      unverified? || requires_update? &&
      required_documents_uploaded? &&
      business_address_complete?
    end
    
    private
    
    def set_defaults
      self.commission_rate ||= SpreeMarketplace.configuration.default_commission_rate
      self.payout_schedule ||= 'monthly'
      self.verification_status ||= 'unverified'
      self.business_type ||= 'individual'
    end
    
    def normalize_tax_id
      return unless tax_id.present?
      
      # Remove common formatting from tax ID
      self.tax_id = tax_id.gsub(/[^\w]/, '').upcase
    end
    
    def validate_business_address
      return unless SpreeMarketplace.configuration.require_business_verification
      
      required_fields = %w[street city state country zipcode]
      missing_fields = required_fields.select { |field| send(field).blank? }
      
      if missing_fields.any?
        errors.add(:business_address, "Missing required fields: #{missing_fields.join(', ')}")
      end
    end
    
    def validate_commission_rate_bounds
      return unless commission_rate.present?
      
      min_rate = 0.05 # 5% minimum
      max_rate = 0.50 # 50% maximum
      
      if commission_rate < min_rate
        errors.add(:commission_rate, "must be at least #{(min_rate * 100).to_i}%")
      elsif commission_rate > max_rate
        errors.add(:commission_rate, "cannot exceed #{(max_rate * 100).to_i}%")
      end
    end
    
    def validate_document_attachments
      return unless SpreeMarketplace.configuration.require_business_verification
      
      if verification_status_pending_verification? || verification_status_verified?
        errors.add(:business_documents, 'must include at least one document') if business_documents.empty?
        errors.add(:identity_documents, 'must include at least one document') if identity_documents.empty?
        
        if SpreeMarketplace.configuration.require_tax_information && tax_documents.empty?
          errors.add(:tax_documents, 'must include at least one document')
        end
      end
    end
    
    def validate_document_sizes
      all_documents = business_documents + tax_documents + identity_documents + bank_documents
      max_size = SpreeMarketplace.configuration.max_document_size
      
      all_documents.each do |document|
        if document.byte_size > max_size
          errors.add(:base, "Document #{document.filename} exceeds maximum size of #{max_size / 1.megabyte}MB")
        end
      end
    end
    
    def validate_document_types
      all_documents = business_documents + tax_documents + identity_documents + bank_documents
      allowed_types = SpreeMarketplace.configuration.allowed_document_types
      
      all_documents.each do |document|
        unless allowed_types.include?(document.content_type)
          errors.add(:base, "Document #{document.filename} has unsupported file type")
        end
      end
    end
  end
end