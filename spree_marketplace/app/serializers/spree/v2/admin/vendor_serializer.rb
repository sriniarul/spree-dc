# frozen_string_literal: true

module Spree
  module V2
    module Admin
      class VendorSerializer
        include JSONAPI::Serializer
        
        set_type :vendor
        set_id :id
        
        # All attributes for admin interface
        attributes :name, :slug, :contact_email, :notification_email, :phone,
                   :about_us, :contact_us, :priority, :state,
                   :created_at, :updated_at
        
        # Computed attributes
        attribute :display_name do |vendor|
          vendor.display_name
        end
        
        attribute :logo_url do |vendor, params|
          return nil unless vendor.image&.attachment&.attached?
          
          Rails.application.routes.url_helpers.url_for(vendor.image.attachment)
        end
        
        attribute :can_be_deleted do |vendor|
          vendor.can_be_deleted?
        end
        
        # State machine transitions
        attribute :available_transitions do |vendor|
          vendor.state_transitions.map(&:event).map(&:to_s)
        end
        
        # Business metrics
        attribute :metrics do |vendor|
          {
            products_count: vendor.products.count,
            active_products_count: vendor.products.available.count,
            orders_count: vendor.orders.count,
            total_sales: vendor.total_sales,
            total_commission: vendor.total_commission_earned,
            pending_payout: vendor.pending_payout_amount,
            total_payouts: vendor.total_payouts
          }
        end
        
        # Categories and tags
        attribute :category_list do |vendor|
          vendor.category_list
        end
        
        attribute :tag_list do |vendor|
          vendor.tag_list
        end
        
        # Recent activity
        attribute :recent_activity do |vendor|
          {
            last_product_created: vendor.products.order(:created_at).last&.created_at,
            last_order_received: vendor.orders.order(:created_at).last&.created_at,
            last_commission_calculated: vendor.order_commissions.order(:created_at).last&.created_at
          }
        end
        
        # Relationships
        has_one :vendor_profile, serializer: VendorProfileSerializer
        
        has_one :image, serializer: ImageSerializer, if: proc { |record|
          record.image&.attachment&.attached?
        }
        
        has_many :products, serializer: ProductSerializer, if: proc { |record, params|
          params && params[:include_products]
        } do |vendor|
          vendor.products.limit(params[:products_limit] || 10)
        end
        
        has_many :order_commissions, serializer: OrderCommissionSerializer, if: proc { |record, params|
          params && params[:include_commissions]
        } do |vendor|
          vendor.order_commissions.recent.limit(10)
        end
        
        has_many :vendor_payouts, serializer: VendorPayoutSerializer, if: proc { |record, params|
          params && params[:include_payouts]
        } do |vendor|
          vendor.vendor_payouts.recent.limit(10)
        end
        
        # Conditional admin-only attributes
        attribute :admin_notes, if: proc { |record, params|
          params && params[:current_user]&.has_spree_role?(:admin)
        } do |vendor|
          vendor.vendor_profile&.notes
        end
        
        attribute :internal_metadata, if: proc { |record, params|
          params && params[:current_user]&.has_spree_role?(:admin)
        } do |vendor|
          vendor.metadata
        end
        
        # Audit information
        attribute :audit_info, if: proc { |record, params|
          params && params[:current_user]&.has_spree_role?(:admin)
        } do |vendor|
          {
            created_by: vendor.created_by,
            updated_by: vendor.updated_by,
            last_state_change: vendor.state_changes.order(:created_at).last&.created_at,
            verification_history: vendor.vendor_profile&.metadata&.dig('commission_rate_history')
          }
        end
        
        # Performance analytics (admin only)
        attribute :performance_analytics, if: proc { |record, params|
          params && params[:current_user]&.has_spree_role?(:admin) && params[:include_analytics]
        } do |vendor|
          date_range = 30.days.ago..Time.current
          
          {
            monthly_sales: vendor.order_commissions.paid_out
                                 .where(created_at: date_range)
                                 .group_by_month(:created_at)
                                 .sum(:base_amount),
            commission_rate_performance: {
              current_rate: vendor.commission_rate,
              average_rate: Spree::VendorProfile.average(:commission_rate),
              rate_comparison: vendor.commission_rate <=> Spree::VendorProfile.average(:commission_rate)
            },
            product_performance: vendor.products.joins(variants: :line_items)
                                      .group('spree_products.name')
                                      .sum('spree_line_items.quantity * spree_line_items.price')
                                      .sort_by { |_, sales| -sales }
                                      .first(5).to_h
          }
        end
        
        # Links for JSONAPI compliance
        attribute :links do |vendor, params|
          base_url = params&.dig(:base_url) || ''
          
          {
            self: "#{base_url}/api/v2/admin/vendors/#{vendor.id}",
            products: "#{base_url}/api/v2/admin/vendors/#{vendor.id}/products",
            orders: "#{base_url}/api/v2/admin/orders?filter[vendor_id]=#{vendor.id}",
            commissions: "#{base_url}/api/v2/admin/vendors/#{vendor.id}/commissions",
            payouts: "#{base_url}/api/v2/admin/vendors/#{vendor.id}/payouts",
            analytics: "#{base_url}/api/v2/admin/vendors/#{vendor.id}/analytics",
            storefront: "#{base_url}/api/v2/storefront/vendors/#{vendor.slug}"
          }
        end
        
        # Action permissions
        attribute :permissions, if: proc { |record, params|
          params && params[:current_user]
        } do |vendor, params|
          ability = params[:current_ability] || Spree::Ability.new(params[:current_user])
          
          {
            can_read: ability.can?(:read, vendor),
            can_edit: ability.can?(:edit, vendor),
            can_delete: ability.can?(:delete, vendor) && vendor.can_be_deleted?,
            can_activate: ability.can?(:update, vendor) && vendor.can_activate?,
            can_suspend: ability.can?(:update, vendor) && vendor.can_suspend?,
            can_block: ability.can?(:update, vendor) && vendor.can_block?,
            can_manage_products: ability.can?(:manage, Spree::Product),
            can_view_analytics: ability.can?(:read, vendor)
          }
        end
        
        # Cache options for performance
        cache_options store: Rails.cache, namespace: 'spree_marketplace_admin', expires_in: 30.minutes
      end
    end
  end
end