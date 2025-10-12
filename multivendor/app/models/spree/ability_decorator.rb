module Spree
  module AbilityDecorator
    def abilities_to_register
      super + [Spree::VendorAbility]
    end

    def apply_admin_permissions(user, options)
      super
      can :manage, Spree::Vendor
      can [:approve, :reject, :suspend, :activate], Spree::Vendor
    end
  end

  Ability.prepend(AbilityDecorator)
end