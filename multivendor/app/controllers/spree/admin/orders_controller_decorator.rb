module Spree
  module Admin
    module OrdersControllerDecorator
      protected

      def scope
        base_scope = super
        vendor = current_vendor

        return base_scope unless vendor&.approved?

        # For vendors, filter orders to only show those containing their products
        vendor_order_ids = Spree::Order.joins(line_items: { variant: :product })
                                       .where(spree_products: { vendor_id: vendor.id })
                                       .distinct
                                       .pluck(:id)

        base_scope.where(id: vendor_order_ids)
      end
    end

    OrdersController.prepend(OrdersControllerDecorator)
  end
end