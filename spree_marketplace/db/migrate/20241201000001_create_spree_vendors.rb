# frozen_string_literal: true

class CreateSpreeVendors < ActiveRecord::Migration[7.0]
  def change
    create_table :spree_vendors do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :business_name
      t.string :contact_email, null: false
      t.string :notification_email
      t.string :phone
      t.text :about_us
      t.text :contact_us
      t.text :meta_description
      t.text :meta_title
      t.string :state, default: 'pending', null: false
      t.integer :priority, default: 0, null: false
      t.datetime :deleted_at
      t.json :metadata, default: {}
      
      t.timestamps null: false
    end
    
    add_index :spree_vendors, :slug, unique: true
    add_index :spree_vendors, :contact_email
    add_index :spree_vendors, :state
    add_index :spree_vendors, :priority
    add_index :spree_vendors, :deleted_at
    add_index :spree_vendors, :created_at
    add_index :spree_vendors, [:state, :priority]
    add_index :spree_vendors, [:deleted_at, :state]
  end
end