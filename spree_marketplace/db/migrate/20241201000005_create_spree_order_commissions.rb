# frozen_string_literal: true

class CreateSpreeOrderCommissions < ActiveRecord::Migration[7.0]
  def change
    create_table :spree_order_commissions do |t|
      t.references :order, null: false, foreign_key: { to_table: :spree_orders }, index: true
      t.references :vendor, null: false, foreign_key: { to_table: :spree_vendors }, index: true
      t.references :line_item, null: true, foreign_key: { to_table: :spree_line_items }, index: true
      t.references :vendor_payout, null: true, foreign_key: { to_table: :spree_vendor_payouts }, index: true
      
      # Financial amounts
      t.decimal :base_amount, precision: 12, scale: 4, default: 0.0, null: false
      t.decimal :commission_rate, precision: 5, scale: 4, default: 0.15, null: false
      t.decimal :commission_amount, precision: 12, scale: 4, default: 0.0, null: false
      t.decimal :platform_fee, precision: 12, scale: 4, default: 0.0, null: false
      t.decimal :vendor_payout, precision: 12, scale: 4, default: 0.0, null: false
      t.decimal :refunded_amount, precision: 12, scale: 4, default: 0.0
      
      # Status and workflow
      t.integer :status, default: 0, null: false
      t.datetime :paid_at
      t.datetime :disputed_at
      t.datetime :cancelled_at
      t.datetime :refunded_at
      
      # Dispute handling
      t.text :dispute_reason
      t.text :cancellation_reason
      t.text :refund_reason
      t.references :disputed_by, null: true, foreign_key: false
      t.references :dispute_resolved_by, null: true, foreign_key: false
      t.datetime :dispute_resolved_at
      
      # Currency support
      t.string :currency, limit: 3
      
      # Metadata
      t.json :metadata, default: {}
      
      t.timestamps null: false
    end
    
    # Unique constraint to prevent duplicate commissions
    add_index :spree_order_commissions, [:vendor_id, :order_id, :line_item_id], 
              unique: true, name: 'index_order_commissions_uniqueness'
    
    # Performance indexes
    add_index :spree_order_commissions, :status
    add_index :spree_order_commissions, :paid_at
    add_index :spree_order_commissions, :created_at
    add_index :spree_order_commissions, [:vendor_id, :status], name: 'index_order_commissions_on_vendor_and_status'
    add_index :spree_order_commissions, [:status, :created_at], name: 'index_order_commissions_on_status_and_date'
    add_index :spree_order_commissions, [:vendor_id, :created_at], name: 'index_order_commissions_on_vendor_and_date'
    
    # Reporting indexes
    add_index :spree_order_commissions, [:vendor_id, :paid_at], name: 'index_order_commissions_vendor_paid'
    add_index :spree_order_commissions, [:vendor_payout_id, :status], name: 'index_order_commissions_payout_status'
  end
end