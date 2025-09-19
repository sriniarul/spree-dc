# frozen_string_literal: true

# VendorConcern adds vendor functionality to existing Spree models
# 
# This concern is automatically included in models specified in the 
# SpreeMarketplace.configuration.vendorized_models array.
# 
# It provides vendor associations, scopes, and helper methods while
# following Spree's existing patterns and conventions.
module Spree
  module VendorConcern
    extend ActiveSupport::Concern
    
    included do
      # Core vendor association - optional to support marketplace products
      belongs_to :vendor, class_name: 'Spree::Vendor', 
                          optional: true, 
                          inverse_of: model_name.plural.to_sym,
                          touch: true
      
      # Vendor-related scopes following Spree patterns
      scope :by_vendor, ->(vendor) { where(vendor: vendor) }
      scope :marketplace_only, -> { where(vendor: nil) }
      scope :vendor_items, -> { where.not(vendor: nil) }
      scope :active_vendor_items, -> { joins(:vendor).where(vendors: { state: 'active' }) }
      scope :for_store_with_vendor, ->(store) do
        if store.present?
          # Multi-store support - get items for store and its vendors
          vendor_ids = store.vendors&.active&.pluck(:id) || []
          where(vendor_id: [nil] + vendor_ids)
        else
          all
        end
      end
      
      # Validation to ensure vendor is active when required
      validates :vendor, presence: true, 
                if: -> { SpreeMarketplace.configuration.vendor_products_require_approval && 
                        self.class.name.demodulize.downcase == 'product' }
      
      validate :vendor_must_be_active, if: :vendor_present_and_active_required?
      validate :vendor_can_manage_item, if: :vendor_present_and_management_required?
      
      # Callbacks for vendor-related functionality
      after_create :notify_vendor_of_new_item, if: :vendor_item?
      after_update :notify_vendor_of_item_changes, if: :vendor_item_with_important_changes?
      before_destroy :check_vendor_deletion_permissions
    end
    
    # Instance methods added to vendorized models
    module InstanceMethods
      # Check if item belongs to marketplace (no vendor)
      def marketplace_item?
        vendor.blank?
      end
      
      # Check if item belongs to a vendor
      def vendor_item?
        vendor.present?
      end
      
      # Get vendor name or 'Marketplace' for display
      def vendor_name
        vendor&.name || Spree.t('marketplace.marketplace')
      end
      
      # Get vendor display name (business name or name)
      def vendor_display_name  
        vendor&.display_name || Spree.t('marketplace.marketplace')
      end
      
      # Check if item can be managed by current vendor user
      def manageable_by_vendor_user?(vendor_user)
        return false unless vendor_user.present?
        return false unless vendor_item?
        return false unless vendor == vendor_user.vendor
        
        case self.class.name.demodulize.downcase
        when 'product'
          vendor_user.can_manage_products?
        when 'variant'
          vendor_user.can_manage_products?
        when 'stock_location'
          vendor_user.can_manage_inventory?
        when 'shipping_method'
          vendor_user.can_manage_settings?
        when 'payment_method'
          vendor_user.can_manage_settings?
        else
          vendor_user.role_owner? || vendor_user.role_manager?
        end
      end
      
      # Check if item can be deleted by vendor user
      def deletable_by_vendor_user?(vendor_user)
        return false unless manageable_by_vendor_user?(vendor_user)
        return false unless SpreeMarketplace.configuration.allow_vendor_product_deletion
        
        case self.class.name.demodulize.downcase
        when 'product'
          vendor_user.can_delete_products?
        else
          vendor_user.role_owner?
        end
      end
      
      # Get commission rate for this item's vendor
      def vendor_commission_rate
        return 0 if marketplace_item?
        
        vendor.commission_rate
      end
      
      # Calculate commission for given amount
      def calculate_vendor_commission(amount)
        return { commission: 0, platform_fee: 0, vendor_payout: amount } if marketplace_item?
        
        SpreeMarketplace.calculate_commission(amount, vendor_commission_rate)
      end
      
      # Check if vendor is active and can sell
      def vendor_active?
        vendor.blank? || vendor.active?
      end
      
      # Get vendor's stock locations for this item type
      def available_vendor_stock_locations
        return Spree::StockLocation.active if marketplace_item?
        
        vendor.stock_locations.active
      end
      
      # Get vendor's shipping methods for this item type  
      def available_vendor_shipping_methods
        return Spree::ShippingMethod.active if marketplace_item?
        
        vendor.shipping_methods.active
      end
      
      private
      
      def vendor_present_and_active_required?
        vendor.present? && SpreeMarketplace.configuration.vendor_products_require_approval
      end
      
      def vendor_present_and_management_required?
        vendor.present? && respond_to?(:manageable_by_vendor?)
      end
      
      def vendor_must_be_active
        return unless vendor.present?
        
        unless vendor.active?
          errors.add(:vendor, Spree.t('marketplace.errors.vendor_must_be_active'))
        end
      end
      
      def vendor_can_manage_item
        return unless respond_to?(:manageable_by_vendor?)
        return if manageable_by_vendor?
        
        errors.add(:vendor, Spree.t('marketplace.errors.vendor_cannot_manage_item'))
      end
      
      def notify_vendor_of_new_item
        return unless vendor.present?
        
        VendorMailer.new_item_notification(self).deliver_later
      end
      
      def vendor_item_with_important_changes?
        vendor_item? && important_attributes_changed?
      end
      
      def important_attributes_changed?
        # Override in specific models to define important attributes
        respond_to?(:name_changed?) && name_changed?
      end
      
      def notify_vendor_of_item_changes
        VendorMailer.item_updated_notification(self).deliver_later
      end
      
      def check_vendor_deletion_permissions
        return true if marketplace_item?
        return true if SpreeMarketplace.configuration.allow_vendor_product_deletion
        
        # If vendor products can't be deleted, check if there are associated records
        if respond_to?(:has_associated_records?) && has_associated_records?
          errors.add(:base, Spree.t('marketplace.errors.cannot_delete_with_associated_records'))
          throw(:abort)
        end
      end
    end
    
    # Class methods added to vendorized models
    module ClassMethods
      # Get all items for a specific vendor including marketplace items
      def for_vendor(vendor)
        if vendor.present?
          where(vendor: [nil, vendor])
        else
          marketplace_only
        end
      end
      
      # Get items that can be managed by a vendor user
      def manageable_by_vendor_user(vendor_user)
        return none unless vendor_user.present?
        
        case name.demodulize.downcase
        when 'product'
          return none unless vendor_user.can_view_orders? # Basic permission check
        when 'variant'
          return none unless vendor_user.can_view_inventory?
        end
        
        by_vendor(vendor_user.vendor)
      end
      
      # Search items by vendor
      def search_by_vendor(term)
        joins(:vendor).where('spree_vendors.name ILIKE ? OR spree_vendors.business_name ILIKE ?', 
                             "%#{term}%", "%#{term}%")
      end
      
      # Get vendor statistics for this model
      def vendor_statistics
        {
          total_count: count,
          marketplace_count: marketplace_only.count,
          vendor_count: vendor_items.count,
          vendors_with_items: vendor_items.distinct.count(:vendor_id)
        }
      end
      
      # Ransack configuration to include vendor searches
      def ransackable_attributes(auth_object = nil)
        attrs = respond_to?(:ransackable_attributes_was) ? 
                ransackable_attributes_was(auth_object) : []
        attrs + %w[vendor_id]
      end
      
      def ransackable_associations(auth_object = nil)
        assocs = respond_to?(:ransackable_associations_was) ? 
                 ransackable_associations_was(auth_object) : []
        assocs + %w[vendor]
      end
    end
    
    # When this concern is included, extend the class with ClassMethods
    # and include InstanceMethods
    def self.included(base)
      base.extend(ClassMethods)
      base.include(InstanceMethods)
      
      # Store original ransack methods if they exist
      if base.respond_to?(:ransackable_attributes)
        base.define_singleton_method(:ransackable_attributes_was, 
                                   base.method(:ransackable_attributes))
      end
      
      if base.respond_to?(:ransackable_associations)
        base.define_singleton_method(:ransackable_associations_was, 
                                   base.method(:ransackable_associations))
      end
    end
  end
end