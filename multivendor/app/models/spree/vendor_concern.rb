module Spree
  module VendorConcern
    extend ActiveSupport::Concern

    included do
      belongs_to :vendor, class_name: 'Spree::Vendor', optional: true

      scope :with_vendor, ->(vendor_id) { where(vendor_id: vendor_id) }
      scope :without_vendor, -> { where(vendor_id: nil) }
    end

    class_methods do
      def accessible_by(ability, action = :index)
        user = ability.send(:user) rescue nil
        vendor = user&.vendor

        if vendor&.approved?
          # Check if this model should be filtered by vendor
          if column_names.include?('vendor_id')
            with_vendor(vendor.id)
          else
            # For models without vendor_id, use original CanCanCan logic
            super(ability, action)
          end
        else
          # For non-vendors or non-approved vendors, use the original CanCanCan behavior
          super(ability, action)
        end
      end
    end

    def vendor_name
      vendor&.display_name
    end

    def has_vendor?
      vendor_id.present?
    end
  end
end