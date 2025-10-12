module Spree
  module Admin
    module Vendor
      class DashboardController < Spree::Admin::BaseController
        before_action :authorize_vendor_access

        def show
          @vendor = current_vendor
          @products_count = current_vendor.products.count
          @active_products_count = current_vendor.products.available.count
          @orders_count = vendor_orders.count
          @pending_orders_count = vendor_orders.where(payment_state: 'balance_due').count

          # Recent orders containing vendor's products
          @recent_orders = vendor_orders.includes(:user, :line_items)
                                       .order(created_at: :desc)
                                       .limit(5)

          # Top selling products
          @top_products = current_vendor.products
                                      .joins(variants: { line_items: :order })
                                      .where(spree_orders: { state: 'complete' })
                                      .group('spree_products.id')
                                      .order('COUNT(spree_line_items.id) DESC')
                                      .limit(5)
        end

        private

        def authorize_vendor_access
          redirect_to spree.admin_forbidden_path unless current_vendor&.approved?
        end

        def vendor_orders
          @vendor_orders ||= Spree::Order.complete
                                         .joins(line_items: { variant: :product })
                                         .where(spree_products: { vendor_id: current_vendor.id })
                                         .distinct
        end
      end
    end
  end
end