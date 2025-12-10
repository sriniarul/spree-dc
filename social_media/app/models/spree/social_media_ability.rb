module Spree
  class SocialMediaAbility
    include CanCan::Ability

    def initialize(user, options = {})
      return unless user

      store = options[:store] if options.key?(:store)

      # Admin permissions
      if user.respond_to?(:has_spree_role?) && user.has_spree_role?('admin')
        # Admin can manage all social media resources
        can :manage, Spree::SocialMediaAccount
        can :manage, Spree::SocialMediaPost
        can :manage, Spree::Campaign if defined?(Spree::Campaign)
        can :manage, Spree::SocialMediaAnalytics
      end

      # Vendor permissions
      if user.respond_to?(:vendor) && user.vendor&.approved?
        vendor = user.vendor

        # Vendor can manage their own social media accounts
        can [:create, :read, :update, :destroy], Spree::SocialMediaAccount, vendor: vendor

        # Vendor can manage their own social media posts
        can [:create, :read, :update, :destroy], Spree::SocialMediaPost do |post|
          post.social_media_account.vendor == vendor
        end

        # Vendor can manage their own campaigns
        if defined?(Spree::Campaign)
          can [:create, :read, :update, :destroy], Spree::Campaign, vendor: vendor
        end

        # Vendor can read their own analytics
        can :read, Spree::SocialMediaAnalytics do |analytics|
          analytics.social_media_account.vendor == vendor
        end

        # Social media specific actions
        can :connect_account, Spree::SocialMediaAccount, vendor: vendor
        can :disconnect_account, Spree::SocialMediaAccount, vendor: vendor
        can :sync_analytics, Spree::SocialMediaAccount, vendor: vendor
        can :test_connection, Spree::SocialMediaAccount, vendor: vendor

        # Post specific actions
        can :schedule, Spree::SocialMediaPost do |post|
          post.social_media_account.vendor == vendor
        end

        can :post_now, Spree::SocialMediaPost do |post|
          post.social_media_account.vendor == vendor && post.draft?
        end

        can :cancel, Spree::SocialMediaPost do |post|
          post.social_media_account.vendor == vendor && post.scheduled?
        end

        # Dashboard access
        can :read, :social_media_dashboard
        can :read, :social_media_analytics_dashboard
      end

      # Store manager permissions (if using store-based multitenancy)
      if user.respond_to?(:has_spree_role?) && store
        if user.has_spree_role?('admin', store)
          can :manage, Spree::SocialMediaAccount, store: store
          can :manage, Spree::SocialMediaPost
          can :manage, Spree::Campaign if defined?(Spree::Campaign)
          can :read, :social_media_dashboard
        end
      end

      # Public permissions (for API access, webhooks, etc.)
      can :create, Spree::SocialMediaAnalytics # For webhook updates
      can :webhook, Spree::SocialMediaAccount # For platform webhooks
    end
  end
end