# frozen_string_literal: true

class AddVendorToSpreeModels < ActiveRecord::Migration[7.0]
  def change
    # Add vendor_id to vendorized models from configuration
    # This migration is dynamic based on SpreeMarketplace configuration
    
    vendorized_models = %w[
      products
      variants
      stock_locations
      shipping_methods
      payment_methods
    ]
    
    vendorized_models.each do |table_name|
      spree_table_name = "spree_#{table_name}"
      
      if table_exists?(spree_table_name)
        add_reference spree_table_name, :vendor, 
                     null: true, 
                     foreign_key: { to_table: :spree_vendors }, 
                     index: true
        
        # Add composite indexes for performance
        case table_name
        when 'products'
          add_index spree_table_name, [:vendor_id, :status], name: 'index_products_on_vendor_and_status'
          add_index spree_table_name, [:vendor_id, :created_at], name: 'index_products_on_vendor_and_created_at'
        when 'variants'
          add_index spree_table_name, [:vendor_id, :is_master], name: 'index_variants_on_vendor_and_is_master'
        when 'stock_locations'
          add_index spree_table_name, [:vendor_id, :active], name: 'index_stock_locations_on_vendor_and_active'
        when 'shipping_methods'
          add_index spree_table_name, [:vendor_id, :deleted_at], name: 'index_shipping_methods_on_vendor_and_deleted_at'
        when 'payment_methods'
          add_index spree_table_name, [:vendor_id, :type], name: 'index_payment_methods_on_vendor_and_type'
        end
      end
    end
  end
  
  def down
    vendorized_models = %w[
      products
      variants  
      stock_locations
      shipping_methods
      payment_methods
    ]
    
    vendorized_models.each do |table_name|
      spree_table_name = "spree_#{table_name}"
      
      if table_exists?(spree_table_name) && column_exists?(spree_table_name, :vendor_id)
        remove_reference spree_table_name, :vendor, foreign_key: { to_table: :spree_vendors }
      end
    end
  end
end