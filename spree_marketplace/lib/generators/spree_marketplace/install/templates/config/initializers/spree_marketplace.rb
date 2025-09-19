# frozen_string_literal: true

# SpreeMarketplace Configuration
# 
# This file is used to configure the SpreeMarketplace gem for your application.
# You can customize various aspects of the multi-vendor marketplace functionality
# by modifying the settings below.

SpreeMarketplace.configure do |config|
  # == Vendorized Models ==
  # 
  # Specify which Spree models should be associated with vendors.
  # By default, products, variants, stock_locations, and shipping_methods are vendorized.
  # 
  # config.vendorized_models = %w[
  #   product
  #   variant
  #   stock_location
  #   shipping_method
  #   payment_method
  # ]

  # == Commission and Fee Settings ==
  # 
  # Default commission rate for vendors (15% by default)
  # config.default_commission_rate = 0.15
  # 
  # Platform fee rate (taken from vendor commission, 3% by default)
  # config.platform_fee_rate = 0.03
  # 
  # Minimum payout amount to vendors
  # config.minimum_payout_amount = 50.00

  # == Vendor Approval Settings ==
  # 
  # Automatically approve new vendors (false by default for security)
  # config.auto_approve_vendors = false
  # 
  # Require business verification documents
  # config.require_business_verification = true
  # 
  # Require tax information from vendors
  # config.require_tax_information = true
  # 
  # Require bank details for payouts
  # config.require_bank_details = true

  # == Product Management ==
  # 
  # Require admin approval for vendor products
  # config.vendor_products_require_approval = true
  # 
  # Allow vendors to delete their products
  # config.allow_vendor_product_deletion = false
  # 
  # Maximum products per vendor (0 for unlimited)
  # config.max_products_per_vendor = 1000

  # == Order Management ==
  # 
  # Split orders by vendor for separate fulfillment
  # config.split_orders_by_vendor = true
  # 
  # Allow vendors to manage their orders
  # config.vendor_can_manage_orders = true
  # 
  # Automatically capture payments for vendor orders
  # config.auto_capture_vendor_payments = false

  # == Email Notifications ==
  # 
  # Send notifications to vendors
  # config.send_vendor_notifications = true
  # 
  # Send notifications to admins
  # config.send_admin_notifications = true
  # 
  # Admin emails for vendor signup notifications
  # config.vendor_signup_notification_emails = 'admin@yourstore.com'

  # == File Upload Settings ==
  # 
  # Maximum vendor logo size (5MB by default)
  # config.max_vendor_logo_size = 5.megabytes
  # 
  # Maximum document size for verification (10MB by default)
  # config.max_document_size = 10.megabytes
  # 
  # Allowed document types
  # config.allowed_document_types = %w[
  #   application/pdf
  #   image/jpeg
  #   image/png
  #   image/gif
  # ]

  # == Analytics and Reporting ==
  # 
  # Enable vendor analytics dashboard
  # config.vendor_analytics_enabled = true
  # 
  # Show marketplace analytics to vendors
  # config.show_marketplace_analytics = true
  # 
  # Data retention period in months
  # config.analytics_data_retention_months = 24

  # == Advanced Features ==
  # 
  # Enable vendor subscription model
  # config.enable_vendor_subscriptions = false
  # 
  # Enable vendor reviews and ratings
  # config.enable_vendor_reviews = true
  # 
  # Enable vendor-to-vendor messaging
  # config.enable_vendor_messaging = false

  # == Multi-Store Support ==
  # 
  # Share vendors across multiple stores
  # config.vendors_shared_across_stores = false
  # 
  # Allow different commission rates per store
  # config.commission_rates_per_store = false
end