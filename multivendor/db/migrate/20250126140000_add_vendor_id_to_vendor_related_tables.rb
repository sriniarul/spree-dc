class AddVendorIdToVendorRelatedTables < ActiveRecord::Migration[7.0]
  def change
    # Add vendor_id to stock_locations
    unless column_exists?(:spree_stock_locations, :vendor_id)
      add_column :spree_stock_locations, :vendor_id, :integer
      add_index :spree_stock_locations, :vendor_id
    end

    # Add vendor_id to shipping_methods
    unless column_exists?(:spree_shipping_methods, :vendor_id)
      add_column :spree_shipping_methods, :vendor_id, :integer
      add_index :spree_shipping_methods, :vendor_id
    end

    # Add vendor_id to orders (for split orders)
    unless column_exists?(:spree_orders, :vendor_id)
      add_column :spree_orders, :vendor_id, :integer
      add_index :spree_orders, :vendor_id
    end

    # Add vendor_id to shipments
    unless column_exists?(:spree_shipments, :vendor_id)
      add_column :spree_shipments, :vendor_id, :integer
      add_index :spree_shipments, :vendor_id
    end
  end
end