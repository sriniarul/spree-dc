module Spree
  module Admin
    module Vendor
      class OrdersController < Spree::Admin::OrdersController
        before_action :authorize_vendor_access

        def index
          params[:q] ||= {}
          @search = orders_scope.ransack(params[:q])
          @orders = @search.result(distinct: true)
                          .includes(:user, :shipments, :bill_address)
                          .page(params[:page])
                          .per(params[:per_page] || 25)
        end

        def show
          @order = find_resource
          @line_items = @order.line_items.joins(:variant => :product)
                              .where(spree_products: { vendor_id: current_vendor.id })
        end

        protected

        def collection
          return Spree::Order.none unless current_vendor

          orders_scope
        end

        def find_resource
          order = orders_scope.find(params[:id])
          # Verify that this order contains products from current vendor
          unless order.line_items.joins(:variant => :product)
                     .exists?(spree_products: { vendor_id: current_vendor.id })
            raise ActiveRecord::RecordNotFound
          end
          order
        end

        private

        def orders_scope
          @orders_scope ||= Spree::Order.complete
                                       .joins(line_items: { variant: :product })
                                       .where(spree_products: { vendor_id: current_vendor.id })
                                       .distinct
        end

        def authorize_vendor_access
          redirect_to spree.admin_forbidden_path unless current_vendor&.approved?
        end

        def location_after_save
          spree.admin_vendor_order_path(@object)
        end

        def collection_url(options = {})
          spree.admin_vendor_orders_path(options)
        end
      end
    end
  end
end