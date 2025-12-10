module Spree
  class Vendor < Spree.base_class
    acts_as_paranoid

    include Spree::Metadata if defined?(Spree::Metadata)

    # Business type constants
    BUSINESS_TYPES = [
      'Sole Proprietorship',
      'Partnership',
      'Private Limited Company',
      'Public Limited Company',
      'Limited Liability Partnership (LLP)',
      'Limited Liability Company (LLC)',
      'Corporation',
      'Cooperative',
      'Non-Profit Organization',
      'Other'
    ].freeze

    # States for vendor approval workflow
    STATES = %w[pending approved rejected suspended].freeze

    # Associations
    has_many :products, class_name: 'Spree::Product', dependent: :restrict_with_error
    has_many :stock_locations, class_name: 'Spree::StockLocation', dependent: :restrict_with_error
    has_many :shipping_methods, class_name: 'Spree::ShippingMethod', dependent: :restrict_with_error

    # Performance optimized associations
    has_many :active_products, -> { where(status: 'active') }, class_name: 'Spree::Product'
    has_many :available_products, -> { available }, class_name: 'Spree::Product'

    belongs_to :country, class_name: 'Spree::Country',
               foreign_key: 'country_code', primary_key: 'iso', optional: true
    belongs_to :user, class_name: Spree.user_class.to_s, optional: true

    # Validations for existing fields
    validates :name, presence: true, length: { maximum: 255 }
    validates :state, presence: true, inclusion: { in: STATES }

    # Validations for new business fields
    validates :legal_name, length: { maximum: 255 }
    validates :business_type, inclusion: { in: BUSINESS_TYPES, allow_blank: true }
    validates :trade_name, length: { maximum: 255 }
    validates :registration_number, length: { maximum: 50 }
    validates :country_code, length: { is: 2, allow_blank: true }
    validates :state_province, length: { maximum: 100 }
    validates :city, length: { maximum: 100 }
    validates :postal_code, length: { maximum: 20 }
    validates :address_line1, length: { maximum: 255 }
    validates :address_line2, length: { maximum: 255 }
    validates :phone_number, format: {
      with: /\A[\+]?[0-9\-\s\(\)]{10,20}\z/,
      message: 'must be a valid phone number',
      allow_blank: true
    }
    validates :website_url, format: {
      with: URI::DEFAULT_PARSER.make_regexp(%w[http https]),
      allow_blank: true
    }

    # Custom validations
    validate :incorporation_date_not_in_future
    validate :registration_number_format_check
    validate :unique_registration_number_per_country

    # Scopes
    scope :approved, -> { where(state: 'approved') }
    scope :pending, -> { where(state: 'pending') }
    scope :rejected, -> { where(state: 'rejected') }
    scope :suspended, -> { where(state: 'suspended') }
    scope :by_business_type, ->(type) { where(business_type: type) }
    scope :by_country, ->(country_code) { where(country_code: country_code) }
    scope :by_state, ->(state) { where(state_province: state) }
    scope :with_complete_registration, -> {
      where.not(legal_name: [nil, ''])
           .where.not(business_type: [nil, ''])
           .where.not(registration_number: [nil, ''])
           .where.not(country_code: [nil, ''])
           .where.not(state_province: [nil, ''])
           .where.not(city: [nil, ''])
           .where.not(postal_code: [nil, ''])
           .where.not(address_line1: [nil, ''])
           .where.not(phone_number: [nil, ''])
    }

    # Callbacks
    before_validation :normalize_business_fields
    before_validation :set_default_state, on: :create
    before_validation :set_display_name_from_business_info
    before_validation :generate_slug

    # State machine methods
    def approve!
      return false unless can_approve?
      update!(state: 'approved')
    end

    def reject!
      return false unless can_reject?
      update!(state: 'rejected')
    end

    def suspend!
      return false unless can_suspend?
      update!(state: 'suspended')
    end

    def activate!
      return false unless can_activate?
      update!(state: 'approved')
    end

    def can_approve?
      pending? && business_registration_complete?
    end

    def can_reject?
      pending?
    end

    def can_suspend?
      approved?
    end

    def can_activate?
      suspended?
    end

    # State check methods
    def pending?
      state == 'pending'
    end

    def approved?
      state == 'approved'
    end

    def rejected?
      state == 'rejected'
    end

    def suspended?
      state == 'suspended'
    end

    # Business information methods
    def display_name
      trade_name.presence || legal_name.presence || name
    end

    def full_business_address
      address_parts = [address_line1]
      address_parts << address_line2 if address_line2.present?
      address_parts << city if city.present?
      address_parts << state_province if state_province.present?
      address_parts << postal_code if postal_code.present?
      address_parts << country&.name if country.present?
      address_parts.compact.join(', ')
    end

    def business_age_in_years
      return 0 unless incorporation_date.present?
      ((Date.current - incorporation_date) / 365.25).to_i
    end

    def business_registration_complete?
      required_fields = %w[legal_name business_type registration_number country_code
                          state_province city postal_code address_line1 phone_number]
      required_fields.all? { |field| self[field].present? }
    end

    def business_registration_percentage
      required_fields = %w[legal_name business_type registration_number country_code
                          state_province city postal_code address_line1 phone_number]
      completed_fields = required_fields.count { |field| self[field].present? }

      optional_fields = %w[trade_name incorporation_date address_line2 website_url]
      completed_optional = optional_fields.count { |field| self[field].present? }

      total_fields = required_fields.count + optional_fields.count
      total_completed = completed_fields + completed_optional

      ((total_completed.to_f / total_fields) * 100).round
    end

    def formatted_phone_number
      return phone_number unless phone_number.present?
      phone_number.gsub(/[^\d+]/, '')
    end

    def business_type_display
      business_type.presence || 'Not Specified'
    end

    private

    def incorporation_date_not_in_future
      return unless incorporation_date.present?

      if incorporation_date > Date.current
        errors.add(:incorporation_date, 'cannot be in the future')
      end
    end

    def registration_number_format_check
      return unless registration_number.present?

      unless registration_number.match(/\A[A-Z0-9\-\.\/\s]{2,50}\z/)
        errors.add(:registration_number, 'must contain only letters, numbers, hyphens, periods, slashes, and spaces')
      end
    end

    def unique_registration_number_per_country
      return unless registration_number.present? && country_code.present?

      existing = self.class.where(registration_number: registration_number, country_code: country_code)
      existing = existing.where.not(id: id) if persisted?

      if existing.exists?
        errors.add(:registration_number, 'is already taken in this country')
      end
    end

    def set_default_state
      self.state ||= 'pending'
    end

    def normalize_business_fields
      self.legal_name = legal_name&.strip&.titleize
      self.trade_name = trade_name&.strip&.titleize
      self.registration_number = registration_number&.strip&.upcase
      self.city = city&.strip&.titleize
      self.state_province = state_province&.strip&.titleize
      self.postal_code = postal_code&.strip&.upcase
      self.country_code = country_code&.strip&.upcase if country_code.present?
      self.phone_number = phone_number&.strip
      self.website_url = website_url&.strip&.downcase
    end

    def set_display_name_from_business_info
      if name.blank?
        candidate_name = trade_name.presence || legal_name.presence
        self.name = candidate_name if candidate_name.present?
      end
    end

    def generate_slug
      if name.present?
        base_slug = name.parameterize
        # Ensure slug is unique
        existing_slugs = self.class.where(slug: base_slug)
        existing_slugs = existing_slugs.where.not(id: id) if persisted?

        if existing_slugs.exists?
          counter = 1
          while self.class.where(slug: "#{base_slug}-#{counter}").exists?
            counter += 1
          end
          self.slug = "#{base_slug}-#{counter}"
        else
          self.slug = base_slug
        end
      elsif slug.blank?
        # Fallback if name is not available
        self.slug = "vendor-#{Time.current.to_i}"
      end
    end
  end
end
