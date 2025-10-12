class AddBusinessFieldsToSpreeVendors < ActiveRecord::Migration[7.0]
  def up
    # Add columns only if they don't exist
    add_column :spree_vendors, :legal_name, :string unless column_exists?(:spree_vendors, :legal_name)
    add_column :spree_vendors, :business_type, :string unless column_exists?(:spree_vendors, :business_type)
    add_column :spree_vendors, :trade_name, :string unless column_exists?(:spree_vendors, :trade_name)
    add_column :spree_vendors, :registration_number, :string unless column_exists?(:spree_vendors, :registration_number)
    add_column :spree_vendors, :incorporation_date, :date unless column_exists?(:spree_vendors, :incorporation_date)
    add_column :spree_vendors, :country_code, :string unless column_exists?(:spree_vendors, :country_code)
    add_column :spree_vendors, :state_province, :string unless column_exists?(:spree_vendors, :state_province)
    add_column :spree_vendors, :city, :string unless column_exists?(:spree_vendors, :city)
    add_column :spree_vendors, :postal_code, :string unless column_exists?(:spree_vendors, :postal_code)
    add_column :spree_vendors, :address_line1, :string unless column_exists?(:spree_vendors, :address_line1)
    add_column :spree_vendors, :address_line2, :string unless column_exists?(:spree_vendors, :address_line2)
    add_column :spree_vendors, :phone_number, :string unless column_exists?(:spree_vendors, :phone_number)
    add_column :spree_vendors, :website_url, :string unless column_exists?(:spree_vendors, :website_url)

    # Add indexes only if they don't exist
    add_index :spree_vendors, :legal_name unless index_exists?(:spree_vendors, :legal_name)
    add_index :spree_vendors, :registration_number unless index_exists?(:spree_vendors, :registration_number)
    add_index :spree_vendors, :business_type unless index_exists?(:spree_vendors, :business_type)
    add_index :spree_vendors, :country_code unless index_exists?(:spree_vendors, :country_code)
    add_index :spree_vendors, :state_province unless index_exists?(:spree_vendors, :state_province)
  end

  def down
    # Remove indexes
    remove_index :spree_vendors, :legal_name if index_exists?(:spree_vendors, :legal_name)
    remove_index :spree_vendors, :registration_number if index_exists?(:spree_vendors, :registration_number)
    remove_index :spree_vendors, :business_type if index_exists?(:spree_vendors, :business_type)
    remove_index :spree_vendors, :country_code if index_exists?(:spree_vendors, :country_code)
    remove_index :spree_vendors, :state_province if index_exists?(:spree_vendors, :state_province)

    # Remove columns
    remove_column :spree_vendors, :legal_name if column_exists?(:spree_vendors, :legal_name)
    remove_column :spree_vendors, :business_type if column_exists?(:spree_vendors, :business_type)
    remove_column :spree_vendors, :trade_name if column_exists?(:spree_vendors, :trade_name)
    remove_column :spree_vendors, :registration_number if column_exists?(:spree_vendors, :registration_number)
    remove_column :spree_vendors, :incorporation_date if column_exists?(:spree_vendors, :incorporation_date)
    remove_column :spree_vendors, :country_code if column_exists?(:spree_vendors, :country_code)
    remove_column :spree_vendors, :state_province if column_exists?(:spree_vendors, :state_province)
    remove_column :spree_vendors, :city if column_exists?(:spree_vendors, :city)
    remove_column :spree_vendors, :postal_code if column_exists?(:spree_vendors, :postal_code)
    remove_column :spree_vendors, :address_line1 if column_exists?(:spree_vendors, :address_line1)
    remove_column :spree_vendors, :address_line2 if column_exists?(:spree_vendors, :address_line2)
    remove_column :spree_vendors, :phone_number if column_exists?(:spree_vendors, :phone_number)
    remove_column :spree_vendors, :website_url if column_exists?(:spree_vendors, :website_url)
  end
end