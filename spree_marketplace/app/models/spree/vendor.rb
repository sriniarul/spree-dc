# frozen_string_literal: true

module Spree
  class Vendor < Spree.base_class
    # Core Spree patterns
    acts_as_paranoid
    acts_as_taggable_on :categories, :tags
    auto_strip_attributes :name, :business_name, :contact_email
    
    # FriendlyId for SEO-friendly URLs
    extend FriendlyId
    friendly_id :name, use: [:slugged, :history, :scoped], scope: :deleted_at
    
    # Spree patterns for translatable content
    include Spree::TranslatableResource
    include Spree::Metadata  
    include Spree::MultiStoreResource if defined?(Spree::MultiStoreResource)
    
    TRANSLATABLE_FIELDS = %i[name about_us contact_us meta_description meta_title].freeze
    
    # State machine for vendor approval workflow
    state_machine :state, initial: :pending do
      event :activate do
        transition pending: :active
        transition suspended: :active
        transition rejected: :pending
      end
      
      event :suspend do
        transition active: :suspended
        transition pending: :suspended
      end
      
      event :reject do
        transition pending: :rejected
        transition active: :rejected
      end
      
      event :block do
        transition [:active, :suspended, :pending, :rejected] => :blocked
      end
      
      # State callbacks following Spree patterns
      after_transition pending: :active do |vendor, _transition|
        vendor.send_activation_email
        vendor.create_default_stock_location
        vendor.assign_default_shipping_categories
      end
      
      after_transition to: :suspended do |vendor, _transition|
        vendor.send_suspension_email
        vendor.deactivate_products
      end
      
      after_transition to: :blocked do |vendor, _transition|
        vendor.send_blocked_email
        vendor.deactivate_all_items
      end
    end
    
    # Associations following Spree patterns
    has_one :vendor_profile, dependent: :destroy, inverse_of: :vendor
    has_one :image, -> { where(type: 'Spree::VendorImage') }, 
            as: :viewable, dependent: :destroy, class_name: 'Spree::Image'
    
    # Vendor user management
    has_many :vendor_users, dependent: :destroy, inverse_of: :vendor
    has_many :users, through: :vendor_users, source: :user
    
    # Core business relationships
    has_many :products, dependent: :restrict_with_exception, inverse_of: :vendor
    has_many :variants, through: :products
    has_many :stock_locations, dependent: :destroy, inverse_of: :vendor
    has_many :shipping_methods, dependent: :destroy, inverse_of: :vendor
    has_many :payment_methods, dependent: :destroy, inverse_of: :vendor
    
    # Financial relationships
    has_many :order_commissions, dependent: :destroy, inverse_of: :vendor
    has_many :vendor_payouts, dependent: :destroy, inverse_of: :vendor
    has_many :orders, through: :order_commissions
    
    # Validations following Spree patterns
    validates :name, presence: true, 
                     uniqueness: { scope: spree_base_uniqueness_scope.push(:deleted_at) },
                     length: { maximum: 255 }
    validates :slug, presence: true, 
                     uniqueness: { scope: spree_base_uniqueness_scope.push(:deleted_at) }
    validates :contact_email, presence: true, 
                              format: { with: URI::MailTo::EMAIL_REGEXP },
                              uniqueness: { scope: spree_base_uniqueness_scope.push(:deleted_at) }
    validates :phone, format: { with: /\A[\+\d\-\(\)\s]+\z/ }, allow_blank: true
    validates :state, inclusion: { in: %w[pending active suspended rejected blocked] }
    validates :priority, numericality: { greater_than_or_equal_to: 0 }
    
    # Nested attributes
    accepts_nested_attributes_for :vendor_profile, allow_destroy: false
    accepts_nested_attributes_for :image, allow_destroy: true, reject_if: :all_blank
    
    # Scopes following Spree patterns
    scope :active, -> { where(state: 'active') }
    scope :pending, -> { where(state: 'pending') }
    scope :suspended, -> { where(state: 'suspended') }
    scope :blocked, -> { where(state: 'blocked') }
    scope :by_priority, -> { order(:priority, :name) }
    scope :by_name, -> { order(:name) }
    scope :recent, -> { order(created_at: :desc) }
    
    # Search scope for admin
    scope :search_by_name, ->(term) { where('name ILIKE ?', "%#{term}%") }
    scope :search_by_email, ->(term) { where('contact_email ILIKE ?', "%#{term}%") }
    
    # Ransack configuration for admin search
    def self.ransackable_attributes(auth_object = nil)
      %w[id name business_name contact_email state priority created_at updated_at]
    end
    
    def self.ransackable_associations(auth_object = nil)
      %w[vendor_profile products orders]
    end
    
    # Business logic methods
    def active?
      state == 'active'
    end
    
    def pending?
      state == 'pending'  
    end
    
    def suspended?
      state == 'suspended'
    end
    
    def blocked?
      state == 'blocked'
    end
    
    def can_be_deleted?
      products.empty? && order_commissions.empty? && vendor_payouts.empty?
    end
    
    def total_sales
      order_commissions.paid.sum(:base_amount)
    end
    
    def total_commission_earned
      order_commissions.paid.sum(:commission_amount)
    end
    
    def total_payouts
      vendor_payouts.completed.sum(:net_amount)
    end
    
    def pending_payout_amount
      order_commissions.calculated.sum(:vendor_payout)
    end
    
    def commission_rate
      vendor_profile&.commission_rate || SpreeMarketplace.configuration.default_commission_rate
    end
    
    # Image helpers following Spree patterns
    def logo
      image
    end
    
    def logo_url(style = nil)
      image&.url(style) || ActionController::Base.helpers.image_path('noimage/large.png')
    end
    
    # Address helpers
    def primary_address
      vendor_profile&.business_address
    end
    
    def display_name
      business_name.presence || name
    end
    
    # Email notification methods
    def send_activation_email
      VendorMailer.activation_notification(self).deliver_later
    end
    
    def send_suspension_email
      VendorMailer.suspension_notification(self).deliver_later
    end
    
    def send_blocked_email
      VendorMailer.blocked_notification(self).deliver_later
    end
    
    # Default stock location creation
    def create_default_stock_location
      return if stock_locations.any?
      
      stock_locations.create!(
        name: "#{name} - Default Location",
        default: true,
        active: true,
        address_attributes: default_stock_location_address
      )
    end
    
    def assign_default_shipping_categories
      default_category = Spree::ShippingCategory.first
      products.includes(:shipping_category).each do |product|
        next if product.shipping_category
        product.update_column(:shipping_category_id, default_category&.id)
      end
    end
    
    def deactivate_products
      products.available.update_all(
        status: 'archived', 
        updated_at: Time.current
      )
    end
    
    def deactivate_all_items
      deactivate_products
      stock_locations.update_all(active: false)
      shipping_methods.update_all(deleted_at: Time.current)
    end
    
    private
    
    def default_stock_location_address
      return {} unless vendor_profile&.business_address
      
      {
        address1: vendor_profile.business_address['street'],
        city: vendor_profile.business_address['city'],
        state_name: vendor_profile.business_address['state'],
        country_iso: vendor_profile.business_address['country'],
        zipcode: vendor_profile.business_address['zipcode']
      }
    end
    
    # Override slug candidates for better SEO
    def slug_candidates
      if deleted_at.present?
        [
          ['deleted', :name],
          ['deleted', :name, :id]
        ]
      else
        [
          [:name],
          [:name, :id]
        ]
      end
    end
    
    def should_generate_new_friendly_id?
      slug.blank? || name_changed?
    end
  end
end