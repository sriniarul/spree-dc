module Spree
  module SocialMediaAbilityExtension
    def abilities_to_register
      super + [Spree::SocialMediaAbility]
    end
  end

  Ability.prepend(SocialMediaAbilityExtension)
end