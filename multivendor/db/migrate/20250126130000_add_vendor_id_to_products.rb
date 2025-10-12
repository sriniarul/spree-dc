class AddVendorIdToProducts < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:spree_products, :vendor_id)
      add_column :spree_products, :vendor_id, :integer
      add_index :spree_products, :vendor_id
    end
  end
end