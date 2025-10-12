module Spree
  module Admin
    module StockLocationsControllerDecorator
      extend ActiveSupport::Concern

      protected

      def collection
        return super unless current_vendor&.approved?

        # For vendors, show only their stock locations and common ones (read-only)
        params[:q] ||= {}
        vendor_stock_locations = Spree::StockLocation.where('vendor_id = ? OR vendor_id IS NULL', current_vendor.id)
        @search = vendor_stock_locations.ransack(params[:q])
        @collection = @search.result(distinct: true)
                             .order(:vendor_id, :name)  # Show vendor-specific first, then common
                             .page(params[:page])
                             .per(params[:per_page])
      end

      def find_resource
        return super unless current_vendor&.approved?

        # Vendors can only access their own stock locations
        current_vendor.stock_locations.find(params[:id])
      end

      def build_resource
        return super unless current_vendor&.approved?

        # When vendors create stock locations, assign them to the vendor
        stock_location = current_vendor.stock_locations.build
        stock_location
      end

      private

      def location_params
        if current_vendor&.approved?
          # Vendors cannot modify the vendor_id - it's automatically set
          params.require(:stock_location).permit(:name, :address1, :address2, :city, :zipcode,
                                                  :phone, :active, :backorderable_default, :propagate_all_variants,
                                                  :admin_name, :state_id, :country_id, :state_name)
        else
          # Admins can set vendor_id
          super.merge(vendor_id: params.dig(:stock_location, :vendor_id))
        end
      end
    end

    StockLocationsController.prepend(StockLocationsControllerDecorator)
  end
end