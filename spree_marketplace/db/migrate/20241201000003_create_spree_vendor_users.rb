# frozen_string_literal: true

class CreateSpreeVendorUsers < ActiveRecord::Migration[7.0]
  def change
    create_table :spree_vendor_users do |t|
      t.references :vendor, null: false, foreign_key: { to_table: :spree_vendors }, index: true
      t.references :user, null: false, index: true
      t.integer :role, default: 0, null: false
      t.integer :invitation_status, default: 0, null: false
      t.json :permissions, default: {}
      
      # Invitation tracking
      t.string :invitation_token
      t.datetime :invited_at
      t.datetime :accepted_at
      t.datetime :declined_at
      t.datetime :expired_at
      t.datetime :revoked_at
      
      t.timestamps null: false
    end
    
    add_index :spree_vendor_users, [:vendor_id, :user_id], unique: true, name: 'index_vendor_users_on_vendor_and_user'
    add_index :spree_vendor_users, :role
    add_index :spree_vendor_users, :invitation_status
    add_index :spree_vendor_users, :invitation_token, unique: true
    add_index :spree_vendor_users, :invited_at
    add_index :spree_vendor_users, [:role, :vendor_id], name: 'index_vendor_users_on_role_and_vendor'
  end
end