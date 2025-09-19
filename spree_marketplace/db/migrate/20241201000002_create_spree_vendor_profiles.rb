# frozen_string_literal: true

class CreateSpreeVendorProfiles < ActiveRecord::Migration[7.0]
  def change
    create_table :spree_vendor_profiles do |t|
      t.references :vendor, null: false, foreign_key: { to_table: :spree_vendors }, index: true
      t.string :business_name, null: false
      t.string :tax_id, null: false
      t.string :business_license_number
      t.integer :business_type, default: 0, null: false
      t.text :encrypted_bank_account_details
      t.json :business_address, default: {}
      t.json :tax_settings, default: {}
      t.json :business_details, default: {}
      t.decimal :commission_rate, precision: 5, scale: 4, default: 0.15, null: false
      t.integer :payout_schedule, default: 2, null: false # monthly
      t.integer :verification_status, default: 0, null: false # unverified
      t.text :notes
      t.json :metadata, default: {}
      
      # Verification tracking
      t.datetime :verification_submitted_at
      t.datetime :verification_approved_at
      t.datetime :verification_rejected_at
      t.text :verification_rejection_reason
      t.references :verification_approved_by, null: true, foreign_key: false
      t.references :verification_rejected_by, null: true, foreign_key: false
      
      t.timestamps null: false
    end
    
    add_index :spree_vendor_profiles, :tax_id, unique: true
    add_index :spree_vendor_profiles, :business_type
    add_index :spree_vendor_profiles, :verification_status
    add_index :spree_vendor_profiles, :commission_rate
    add_index :spree_vendor_profiles, :payout_schedule
    add_index :spree_vendor_profiles, :verification_submitted_at
    add_index :spree_vendor_profiles, [:verification_status, :verification_submitted_at], 
              name: 'index_vendor_profiles_on_verification'
  end
end