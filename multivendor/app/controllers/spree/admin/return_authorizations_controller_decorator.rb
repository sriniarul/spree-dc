module Spree
  module Admin
    module ReturnAuthorizationsControllerDecorator
      protected

      def collection
        return super unless current_vendor&.approved?

        # For vendors, filter return authorizations to only show those for their products
        vendor_returns = Spree::ReturnAuthorization.joins(return_items: { inventory_unit: { line_item: { variant: :product } } })
                                                   .where(spree_products: { vendor_id: current_vendor.id })
                                                   .distinct

        params[:q] ||= {}
        @search = vendor_returns.ransack(params[:q])
        @collection = @search.result(distinct: true)
                             .includes(:order, :return_items)
                             .page(params[:page])
                             .per(params[:per_page])
      end
    end

    ReturnAuthorizationsController.prepend(ReturnAuthorizationsControllerDecorator)
  end
end