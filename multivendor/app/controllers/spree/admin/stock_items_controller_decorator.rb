module Spree
  module Admin
    module StockItemsControllerDecorator
      protected

      def collection
        return super unless current_vendor&.approved?

        # For vendors, filter stock items to show those from both their own stock locations
        # and common stock locations, but only for their products
        vendor_stock_items = Spree::StockItem.joins(:stock_location, :variant => :product)
                                             .where('spree_stock_locations.vendor_id = ? OR spree_stock_locations.vendor_id IS NULL', current_vendor.id)
                                             .where(spree_products: { vendor_id: current_vendor.id })

        params[:q] ||= {}
        @search = vendor_stock_items.ransack(params[:q])
        @collection = @search.result(distinct: true)
                             .includes(:stock_location, variant: [:product, :option_values])
                             .page(params[:page])
                             .per(params[:per_page])
      end
    end

    StockItemsController.prepend(StockItemsControllerDecorator)
  end
end