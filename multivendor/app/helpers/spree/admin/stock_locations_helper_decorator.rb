module Spree
  module Admin
    module StockLocationsHelperDecorator
      extend ActiveSupport::Concern

      def available_stock_locations(_opts = {})
        if respond_to?(:current_vendor) && current_vendor&.approved?
          # For vendors, show both their own stock locations and common ones
          Spree::StockLocation.where('vendor_id = ? OR vendor_id IS NULL', current_vendor.id)
                              .order_default
                              .active
                              .accessible_by(current_ability)
        else
          # For admins, show all stock locations
          super
        end
      end

      def available_stock_locations_for_product(product)
        if respond_to?(:current_vendor) && current_vendor&.approved?
          # For vendors, filter stock locations based on vendor access
          available_stock_locations
        else
          # For admins, use default behavior
          super
        end
      end

      def default_stock_location_for_product(product)
        if respond_to?(:current_vendor) && current_vendor&.approved?
          # For vendors, try to use their own stock location first, then fall back to common
          vendor_stock_location = Spree::StockLocation.where(vendor_id: current_vendor.id).active.first
          vendor_stock_location || Spree::StockLocation.where(vendor_id: nil).active.first || current_store.default_stock_location
        else
          # For admins, use default behavior
          super
        end
      end

      # Enhanced list with vendor context
      def available_stock_locations_list(opts = {})
        if respond_to?(:current_vendor) && current_vendor&.approved?
          available_stock_locations(opts).map do |stock_location|
            vendor_info = stock_location.vendor_id ? "(#{stock_location.vendor.name})" : "(Common)"
            ["#{stock_location.name} #{vendor_info}", stock_location.id]
          end
        else
          super
        end
      end
    end

    # Include the decorator in the helper
    StockLocationsHelper.prepend(StockLocationsHelperDecorator)
  end
end