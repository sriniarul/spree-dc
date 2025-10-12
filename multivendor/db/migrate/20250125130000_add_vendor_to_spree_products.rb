class AddVendorToSpreeProducts < ActiveRecord::Migration[7.0]
  def up
    unless column_exists?(:spree_products, :vendor_id)
      add_reference :spree_products, :vendor, foreign_key: { to_table: :spree_vendors }, null: true
    end

    add_index :spree_products, :vendor_id unless index_exists?(:spree_products, :vendor_id)
  end

  def down
    remove_index :spree_products, :vendor_id if index_exists?(:spree_products, :vendor_id)
    remove_reference :spree_products, :vendor if column_exists?(:spree_products, :vendor_id)
  end
end