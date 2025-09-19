# frozen_string_literal: true

module Spree
  class OrderCommission < Spree.base_class
    # Core Spree patterns
    include Spree::Metadata
    
    # Associations following Spree patterns
    belongs_to :order, inverse_of: :order_commissions
    belongs_to :vendor, inverse_of: :order_commissions  
    belongs_to :line_item, optional: true, inverse_of: :order_commission
    belongs_to :vendor_payout, optional: true, inverse_of: :order_commissions
    
    # Commission status
    enum status: {
      pending: 0,       # Order created, commission not calculated
      calculated: 1,    # Commission calculated, ready for payout
      paid: 2,          # Commission paid to vendor
      disputed: 3,      # Commission disputed by vendor or admin
      cancelled: 4,     # Order cancelled, commission voided
      refunded: 5       # Partial or full refund processed
    }, _prefix: true
    
    # Validations following Spree patterns
    validates :order, presence: true
    validates :vendor, presence: true
    validates :base_amount, presence: true, 
                            numericality: { greater_than_or_equal_to: 0 }
    validates :commission_rate, presence: true,
                                numericality: { 
                                  greater_than_or_equal_to: 0,
                                  less_than_or_equal_to: 1
                                }
    validates :commission_amount, presence: true,
                                  numericality: { greater_than_or_equal_to: 0 }
    validates :platform_fee, presence: true,
                             numericality: { greater_than_or_equal_to: 0 }
    validates :vendor_payout, numericality: { greater_than_or_equal_to: 0 }
    validates :status, presence: true
    
    # Ensure unique commission per vendor per order (or per line item if line-item based)
    validates :vendor_id, uniqueness: { 
      scope: [:order_id, :line_item_id],
      message: 'Commission already exists for this vendor and order/line item'
    }
    
    # Monetary attributes for Spree money display
    money_methods :base_amount, :commission_amount, :platform_fee, :vendor_payout, :refunded_amount
    
    # Callbacks
    before_validation :calculate_commission_amounts, if: :should_calculate_commission?
    before_validation :set_commission_rate, if: :commission_rate.blank?
    after_create :update_order_vendor_total
    after_update :update_order_vendor_total, if: :saved_change_to_vendor_payout?
    
    # Scopes for filtering and reporting
    scope :by_vendor, ->(vendor) { where(vendor: vendor) }
    scope :by_order_state, ->(state) { joins(:order).where(orders: { state: state }) }
    scope :completed_orders, -> { joins(:order).where(orders: { state: 'complete' }) }
    scope :recent, -> { order(created_at: :desc) }
    scope :for_payout, -> { where(status: :calculated) }
    scope :paid_out, -> { where(status: :paid) }
    scope :disputed, -> { where(status: :disputed) }
    scope :by_date_range, ->(start_date, end_date) { where(created_at: start_date..end_date) }
    
    # Reporting scopes
    scope :this_month, -> { where(created_at: Date.current.beginning_of_month..Date.current.end_of_month) }
    scope :last_month, -> { where(created_at: 1.month.ago.beginning_of_month..1.month.ago.end_of_month) }
    scope :this_year, -> { where(created_at: Date.current.beginning_of_year..Date.current.end_of_year) }
    
    # Ransack configuration for admin search
    def self.ransackable_attributes(auth_object = nil)
      %w[id base_amount commission_amount vendor_payout status created_at updated_at 
         commission_rate platform_fee]
    end
    
    def self.ransackable_associations(auth_object = nil)  
      %w[order vendor line_item vendor_payout]
    end
    
    # Business logic methods
    def commission_percentage
      (commission_rate * 100).round(2) if commission_rate.present?
    end
    
    def platform_fee_percentage  
      return 0 unless commission_amount > 0
      
      ((platform_fee / commission_amount) * 100).round(2)
    end
    
    def net_vendor_percentage
      return 0 unless base_amount > 0
      
      ((vendor_payout / base_amount) * 100).round(2)
    end
    
    def can_be_paid?
      status_calculated? && order.completed? && vendor.active?
    end
    
    def can_be_disputed?
      status_calculated? || status_paid?
    end
    
    def can_be_cancelled?
      !status_paid? && !status_cancelled?
    end
    
    def order_completed?
      order.completed?
    end
    
    def vendor_active?
      vendor.active?
    end
    
    def ready_for_payout?
      can_be_paid? && 
      vendor_payout >= SpreeMarketplace.configuration.minimum_payout_amount
    end
    
    # Commission workflow methods
    def mark_as_calculated!
      return false unless status_pending?
      
      calculate_commission_amounts
      update!(status: :calculated)
      
      VendorMailer.commission_calculated(self).deliver_later
      true
    end
    
    def mark_as_paid!(payout = nil)
      return false unless can_be_paid?
      
      transaction do
        update!(
          status: :paid,
          paid_at: Time.current,
          vendor_payout: payout
        )
        
        vendor_payout.update!(status: :paid) if vendor_payout.present?
      end
      
      VendorMailer.commission_paid(self).deliver_later
      true
    rescue ActiveRecord::RecordInvalid
      false
    end
    
    def dispute!(reason, disputed_by = nil)
      return false unless can_be_disputed?
      
      update!(
        status: :disputed,
        disputed_at: Time.current,
        dispute_reason: reason,
        disputed_by: disputed_by
      )
      
      VendorMailer.commission_disputed(self, reason).deliver_later
      AdminMailer.commission_dispute_alert(self, reason).deliver_later
      true
    end
    
    def resolve_dispute!(resolved_by = nil)
      return false unless status_disputed?
      
      update!(
        status: :calculated,
        dispute_resolved_at: Time.current,
        dispute_resolved_by: resolved_by,
        dispute_reason: nil
      )
      
      VendorMailer.commission_dispute_resolved(self).deliver_later
      true
    end
    
    def cancel!(reason = nil)
      return false unless can_be_cancelled?
      
      update!(
        status: :cancelled,
        cancelled_at: Time.current,
        cancellation_reason: reason
      )
      
      true
    end
    
    def process_refund!(refund_amount, reason = nil)
      return false unless status_paid? || status_calculated?
      return false if refund_amount > vendor_payout
      
      self.refunded_amount = (self.refunded_amount || 0) + refund_amount
      
      if refunded_amount >= vendor_payout
        self.status = :refunded
      end
      
      self.refund_reason = reason if reason.present?
      self.refunded_at = Time.current
      
      save!
      
      VendorMailer.commission_refunded(self, refund_amount, reason).deliver_later
      true
    end
    
    # Reporting methods
    def self.total_for_vendor(vendor, date_range = nil)
      scope = by_vendor(vendor).paid_out
      scope = scope.where(created_at: date_range) if date_range
      scope.sum(:vendor_payout)
    end
    
    def self.total_platform_fees(date_range = nil)
      scope = paid_out
      scope = scope.where(created_at: date_range) if date_range  
      scope.sum(:platform_fee)
    end
    
    def self.commission_summary(date_range = nil)
      scope = all
      scope = scope.where(created_at: date_range) if date_range
      
      {
        total_orders: scope.joins(:order).distinct.count('orders.id'),
        total_base_amount: scope.sum(:base_amount),
        total_commission: scope.sum(:commission_amount),
        total_platform_fees: scope.sum(:platform_fee),
        total_vendor_payouts: scope.sum(:vendor_payout),
        pending_count: scope.status_pending.count,
        calculated_count: scope.status_calculated.count,
        paid_count: scope.status_paid.count,
        disputed_count: scope.status_disputed.count
      }
    end
    
    def self.vendor_performance_report(vendor, date_range = nil)
      scope = by_vendor(vendor)
      scope = scope.where(created_at: date_range) if date_range
      
      {
        vendor: vendor,
        total_orders: scope.joins(:order).distinct.count('orders.id'),
        total_sales: scope.sum(:base_amount),
        total_commission: scope.sum(:commission_amount),
        total_payout: scope.sum(:vendor_payout),
        average_commission_rate: scope.average(:commission_rate),
        pending_amount: scope.status_calculated.sum(:vendor_payout),
        paid_amount: scope.status_paid.sum(:vendor_payout)
      }
    end
    
    private
    
    def should_calculate_commission?
      base_amount.present? && (commission_amount.blank? || base_amount_changed? || commission_rate_changed?)
    end
    
    def set_commission_rate
      self.commission_rate = vendor&.commission_rate || 
                           SpreeMarketplace.configuration.default_commission_rate
    end
    
    def calculate_commission_amounts
      return unless base_amount.present? && commission_rate.present?
      
      commission_data = SpreeMarketplace.calculate_commission(base_amount, commission_rate)
      
      self.commission_amount = commission_data[:commission]
      self.platform_fee = commission_data[:platform_fee] 
      self.vendor_payout = commission_data[:vendor_payout]
    end
    
    def update_order_vendor_total
      # Update order's vendor-specific totals if needed
      return unless order.respond_to?(:update_vendor_totals)
      
      order.update_vendor_totals
    end
  end
end