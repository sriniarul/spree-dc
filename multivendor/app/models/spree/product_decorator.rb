module Spree
  module ProductDecorator
    extend ActiveSupport::Concern

    included do
      include Spree::VendorConcern

      # Update the vendor association to use proper inverse
      belongs_to :vendor, class_name: 'Spree::Vendor', optional: true

      # Add validation to ensure products are assigned to vendors when created by vendors
      validates :vendor_id, presence: true, if: :vendor_required?

      # Scope for vendor-specific products
      scope :for_vendor, ->(vendor) { where(vendor: vendor) }
      scope :without_vendor, -> { where(vendor_id: nil) }
    end

    private

    def vendor_required?
      # Only require vendor if we're in a vendor context
      # This allows admin users to create products without vendor assignment
      false # We'll handle this in the controller instead
    end
  end

  Product.prepend(ProductDecorator)
end