# frozen_string_literal: true

class CreateSpreeVendorPayouts < ActiveRecord::Migration[7.0]
  def change
    create_table :spree_vendor_payouts do |t|
      t.references :vendor, null: false, foreign_key: { to_table: :spree_vendors }, index: true
      
      # Payout period
      t.date :payout_period_start, null: false
      t.date :payout_period_end, null: false
      
      # Financial amounts
      t.decimal :total_commission, precision: 12, scale: 4, default: 0.0, null: false
      t.decimal :platform_fees, precision: 12, scale: 4, default: 0.0, null: false
      t.decimal :adjustments, precision: 12, scale: 4, default: 0.0
      t.decimal :net_amount, precision: 12, scale: 4, default: 0.0, null: false
      
      # Status and processing
      t.integer :status, default: 0, null: false # pending, processing, completed, failed, cancelled
      t.datetime :processed_at
      t.datetime :completed_at
      t.datetime :failed_at
      t.datetime :cancelled_at
      
      # Payment information
      t.string :payment_method
      t.string :payment_reference
      t.text :payment_details
      t.text :failure_reason
      
      # Batch information
      t.string :batch_id
      t.references :processed_by, null: true, foreign_key: false
      
      # Currency
      t.string :currency, limit: 3, default: 'USD'
      
      # Metadata and notes
      t.text :notes
      t.json :metadata, default: {}
      
      t.timestamps null: false
    end
    
    # Indexes for performance and querying
    add_index :spree_vendor_payouts, :status
    add_index :spree_vendor_payouts, :processed_at
    add_index :spree_vendor_payouts, :completed_at
    add_index :spree_vendor_payouts, [:vendor_id, :status], name: 'index_vendor_payouts_on_vendor_and_status'
    add_index :spree_vendor_payouts, [:status, :processed_at], name: 'index_vendor_payouts_on_status_and_processed'
    add_index :spree_vendor_payouts, [:payout_period_start, :payout_period_end], name: 'index_vendor_payouts_on_period'
    add_index :spree_vendor_payouts, :batch_id
    add_index :spree_vendor_payouts, :payment_reference
    
    # Unique constraint for payout periods per vendor
    add_index :spree_vendor_payouts, [:vendor_id, :payout_period_start, :payout_period_end], 
              unique: true, name: 'index_vendor_payouts_unique_period'
  end
end