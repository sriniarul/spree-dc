module Spree
  class VendorAbility
    include CanCan::Ability

    def initialize(user, options = {})
      return unless user.persisted?

      vendor = user.vendor
      return unless vendor&.approved?

      # Vendor Dashboard Access - vendors should not have access to main dashboard
      cannot :admin, :dashboard
      cannot :show, :dashboard

      # Allow vendors to manage their own vendor profile
      can [:show, :edit, :update], Spree::Vendor, user_id: user.id

      # Allow vendors to manage their own products - use hash conditions for SQL compatibility
      can :manage, Spree::Product, vendor_id: vendor.id

      # For variants, we need to use a different approach since they don't have vendor_id directly
      can :manage, Spree::Variant, product: { vendor_id: vendor.id }

      # For orders, we'll handle this in controller decorators since the relationship is complex
      can :read, Spree::Order
      can :read, Spree::LineItem

      # Allow vendors to read their own returns (filtering handled in controller decorators)
      can :read, Spree::ReturnAuthorization
      can :read, Spree::CustomerReturn
      can :read, Spree::ReturnItem
      can :read, Spree::Refund

      # Allow vendors to manage their stock - use hash conditions
      can :manage, Spree::StockLocation, vendor_id: vendor.id
      can :read, Spree::StockLocation, vendor_id: nil  # Allow reading common stock locations
      can :manage, Spree::StockItem, stock_location: { vendor_id: vendor.id }

      # Allow vendors to read shipping methods for their products
      can :read, Spree::ShippingMethod, vendor_id: vendor.id

      # Allow vendors to see basic store information
      can :read, Spree::Store
      can :read, Spree::Country
      can :read, Spree::State
      can :read, Spree::TaxCategory
      can :read, Spree::ShippingCategory

      # Allow vendors to read taxons/categories (needed for product categorization)
      can :read, Spree::Taxonomy
      can :read, Spree::Taxon
      can :select_options, Spree::Taxon  # Needed for the taxon selection dropdown

      # Allow vendors to read properties and option types (needed for product management)
      can :read, Spree::Property
      can :read, Spree::OptionType
      can :read, Spree::OptionValue

      # Allow vendors to manage their own profile/account
      can [:show, :edit, :update], user.class, id: user.id

      # Explicitly deny access to admin-only features
      cannot :admin, :dashboard  # Main admin dashboard
      cannot :manage, Spree::User
      cannot :manage, Spree::Promotion
      cannot :manage, Spree::Report
      cannot :manage, Spree::Admin
      cannot [:create, :update, :destroy], Spree::Taxonomy
      cannot [:create, :update, :destroy], Spree::Taxon
      cannot [:create, :update, :destroy], Spree::Property
      cannot [:create, :update, :destroy], Spree::OptionType
      cannot :manage, Spree::PaymentMethod
      cannot :manage, Spree::Role
      cannot :manage, :store_settings
      cannot :manage, :admin_settings

      # Deny vendor access to admin sections for taxonomies, properties, and option types
      cannot :admin, Spree::Taxonomy
      cannot :admin, Spree::Taxon
      cannot :admin, Spree::Property
      cannot :admin, Spree::OptionType
      cannot :admin, Spree::OptionValue
      cannot :index, Spree::Taxonomy
      cannot :index, Spree::Property
      cannot :index, Spree::OptionType
      cannot :manage, Spree::Taxonomy
      cannot :manage, Spree::Property
      cannot :manage, Spree::OptionType

      # Deny access to storefront management
      cannot :manage, Spree::Theme
      cannot :manage, Spree::Page
      cannot :manage, Spree::Post

      # Deny access to integrations
      cannot :manage, Spree::Integration

      # Vendors cannot manage the store itself or other vendors
      cannot :manage, Spree::Store

      # For complex relationships that can't be expressed as hash conditions,
      # we'll handle filtering in controller decorators
    end
  end
end
