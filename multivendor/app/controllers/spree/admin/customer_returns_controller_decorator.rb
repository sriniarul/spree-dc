module Spree
  module Admin
    module CustomerReturnsControllerDecorator
      protected

      def collection
        return super unless current_vendor&.approved?

        # For vendors, filter customer returns to only show those for their products
        vendor_returns = Spree::CustomerReturn.joins(return_items: { inventory_unit: { line_item: { variant: :product } } })
                                              .where(spree_products: { vendor_id: current_vendor.id })
                                              .distinct

        params[:q] ||= {}
        @search = vendor_returns.ransack(params[:q])
        @collection = @search.result(distinct: true)
                             .includes(:return_items, :stock_location)
                             .page(params[:page])
                             .per(params[:per_page])
      end
    end

    CustomerReturnsController.prepend(CustomerReturnsControllerDecorator)
  end
end