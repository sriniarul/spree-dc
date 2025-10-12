module Spree
  module UserDecorator
    def self.prepended(base)
      base.has_one :vendor, class_name: 'Spree::Vendor', dependent: :destroy
    end

    def vendor_admin?
      vendor&.approved?
    end

    def spree_admin?(store = nil)
      return true if super
      vendor_admin?
    end
  end

  Spree.user_class.prepend(UserDecorator)
end