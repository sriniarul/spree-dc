# frozen_string_literal: true

module SpreeMarketplace
  # Configuration class for SpreeMarketplace gem
  # 
  # This class follows the same patterns as Spree core configuration,
  # allowing for flexible customization of the marketplace behavior.
  class Configuration < Spree::Preferences::Configuration
    # Models that can be associated with vendors
    # Can be extended to include custom models
    preference :vendorized_models, :array, default: %w[
      product
      variant  
      stock_location
      shipping_method
      payment_method
    ]
    
    # Commission and fee settings
    preference :default_commission_rate, :decimal, default: 0.15
    preference :platform_fee_rate, :decimal, default: 0.03
    preference :minimum_payout_amount, :decimal, default: 50.00
    
    # Vendor approval settings  
    preference :auto_approve_vendors, :boolean, default: false
    preference :require_business_verification, :boolean, default: true
    preference :require_tax_information, :boolean, default: true
    preference :require_bank_details, :boolean, default: true
    
    # Email notification settings
    preference :send_vendor_notifications, :boolean, default: true
    preference :send_admin_notifications, :boolean, default: true
    preference :vendor_signup_notification_emails, :string, default: 'admin@example.com'
    
    # Product management settings
    preference :vendor_products_require_approval, :boolean, default: true
    preference :allow_vendor_product_deletion, :boolean, default: false
    preference :max_products_per_vendor, :integer, default: 1000
    
    # Order management settings
    preference :split_orders_by_vendor, :boolean, default: true
    preference :vendor_can_manage_orders, :boolean, default: true
    preference :auto_capture_vendor_payments, :boolean, default: false
    
    # Dashboard and reporting settings  
    preference :vendor_analytics_enabled, :boolean, default: true
    preference :show_marketplace_analytics, :boolean, default: true
    preference :analytics_data_retention_months, :integer, default: 24
    
    # File upload settings
    preference :max_vendor_logo_size, :integer, default: 5.megabytes
    preference :max_document_size, :integer, default: 10.megabytes
    preference :allowed_document_types, :array, default: %w[
      application/pdf
      image/jpeg
      image/png
      image/gif
    ]
    
    # Search and filtering
    preference :enable_vendor_search, :boolean, default: true
    preference :vendors_per_page, :integer, default: 20
    preference :vendor_products_per_page, :integer, default: 50
    
    # Multi-store support
    preference :vendors_shared_across_stores, :boolean, default: false
    preference :commission_rates_per_store, :boolean, default: false
    
    # Advanced features
    preference :enable_vendor_subscriptions, :boolean, default: false
    preference :enable_vendor_reviews, :boolean, default: true
    preference :enable_vendor_messaging, :boolean, default: false
    
    # Validation method for vendorized models
    def validate_vendorized_models
      invalid_models = vendorized_models - %w[
        product variant stock_location shipping_method payment_method
        promotion taxonomy taxon option_type property
      ]
      
      unless invalid_models.empty?
        raise ArgumentError, "Invalid vendorized models: #{invalid_models.join(', ')}"
      end
    end
    
    # Helper method to check if a model is vendorized
    def model_vendorized?(model_name)
      vendorized_models.include?(model_name.to_s)
    end
    
    # Helper method for commission calculation
    def calculate_commission(amount, vendor_rate = nil)
      rate = vendor_rate || default_commission_rate
      commission = amount * rate
      platform_fee = commission * platform_fee_rate
      vendor_payout = commission - platform_fee
      
      {
        commission: commission,
        platform_fee: platform_fee,
        vendor_payout: vendor_payout
      }
    end
  end
end