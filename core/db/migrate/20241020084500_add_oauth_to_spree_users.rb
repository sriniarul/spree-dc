class AddOauthToSpreeUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :spree_users, :provider, :string
    add_column :spree_users, :uid, :string
    add_column :spree_users, :first_name, :string
    add_column :spree_users, :last_name, :string
    add_column :spree_users, :image_url, :string

    # Add indexes for OAuth lookups
    add_index :spree_users, [:provider, :uid], unique: true
    add_index :spree_users, :email
  end
end