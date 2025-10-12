module Spree
  module StockLocationDecorator
    extend ActiveSupport::Concern

    included do
      # Scope for stock locations accessible by a specific vendor
      # Includes both vendor-specific and common (vendor_id = nil) stock locations
      scope :accessible_by_vendor, ->(vendor) {
        where('vendor_id = ? OR vendor_id IS NULL', vendor.id)
      }

      # Scope for common/shared stock locations (available to all vendors)
      scope :common, -> { where(vendor_id: nil) }

      # Scope for vendor-specific stock locations only
      scope :vendor_specific, ->(vendor) { where(vendor_id: vendor.id) }
    end

    # Check if this stock location belongs to a specific vendor
    def vendor_specific?
      vendor_id.present?
    end

    # Check if this is a common/shared stock location
    def common?
      vendor_id.nil?
    end

    # Display name with vendor context
    def display_name_with_vendor
      if vendor_specific?
        "#{name} (#{vendor.display_name})"
      else
        "#{name} (Common)"
      end
    end
  end

  StockLocation.include(StockLocationDecorator)
end