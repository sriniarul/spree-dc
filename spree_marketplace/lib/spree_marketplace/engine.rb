# frozen_string_literal: true

require 'spree/core'
require 'state_machines-activerecord'

module SpreeMarketplace
  class Engine < Rails::Engine
    require 'spree/core'
    isolate_namespace Spree
    engine_name 'spree_marketplace'

    # Use rspec for testing
    config.generators do |g|
      g.test_framework :rspec
      g.factory_bot dir: 'spec/factories'
    end

    def self.activate
      # Load application-level decorators
      Dir.glob(File.join(File.dirname(__FILE__), '../../app/**/*_decorator*.rb')) do |c|
        Rails.configuration.cache_classes ? require(c) : load(c)
      end

      # Add vendor_id to permitted product attributes following Spree patterns
      if Spree::PermittedAttributes.respond_to?(:product_attributes)
        Spree::PermittedAttributes.product_attributes << :vendor_id
      end
      
      if Spree::PermittedAttributes.respond_to?(:variant_attributes)
        Spree::PermittedAttributes.variant_attributes << :vendor_id
      end

      if Spree::PermittedAttributes.respond_to?(:stock_location_attributes)
        Spree::PermittedAttributes.stock_location_attributes << :vendor_id
      end

      if Spree::PermittedAttributes.respond_to?(:shipping_method_attributes)
        Spree::PermittedAttributes.shipping_method_attributes << :vendor_id
      end
    end

    # Configure the engine
    config.to_prepare(&method(:activate).to_proc)
    
    # Add translations
    initializer 'spree_marketplace.add_translations' do |app|
      config.i18n.load_path += Dir[File.join(File.dirname(__FILE__), '../../config', 'locales', '*.yml')]
    end
    
    # Add view paths for admin interface
    initializer 'spree_marketplace.add_view_paths' do
      ActionController::Base.prepend_view_path File.join(root, 'app', 'views')
    end
    
    # Configure assets  
    initializer 'spree_marketplace.assets.precompile' do |app|
      app.config.assets.precompile += %w(
        spree/admin/marketplace.js
        spree/admin/marketplace.css
        spree/vendors/dashboard.js
        spree/vendors/dashboard.css
      )
    end
    
    # Add migrations path
    initializer 'spree_marketplace.migrations' do |app|
      unless app.root.to_s.match(root.to_s)
        config.paths['db/migrate'].expanded.each do |expanded_path|
          app.config.paths['db/migrate'] << expanded_path
        end
      end
    end
    
    # Configure importmap for Stimulus controllers
    initializer 'spree_marketplace.importmap', before: 'importmap' do |app|
      if app.config.respond_to?(:importmap)
        app.config.importmap.paths << root.join('app/javascript')
        app.config.importmap.cache_sweepers << root.join('app/javascript')
      end
    end
    
    # Integrate with Spree backend abilities
    initializer 'spree_marketplace.register_abilities' do
      Spree::Ability.register_ability(SpreeMarketplace::Ability)
    end
    
    # Auto-load concerns and extend models
    config.autoload_paths += [
      "#{config.root}/app/models/concerns"
    ]
    
    # Load vendor concern into vendorized models
    config.to_prepare do
      # Extend models with vendor functionality
      SpreeMarketplace.configuration.vendorized_models.each do |model_name|
        model_class_name = "Spree::#{model_name.camelize}"
        
        if Object.const_defined?(model_class_name)
          model_class = model_class_name.constantize
          model_class.include Spree::VendorConcern unless model_class.included_modules.include?(Spree::VendorConcern)
        end
      end
      
      # Extend Order model for vendor functionality
      Spree::Order.include Spree::Order::VendorExtensions if defined?(Spree::Order)
      
      # Extend User model for vendor associations
      if Spree.user_class
        Spree.user_class.include Spree::UserVendorExtensions
      end
    end
    
    # Add admin menu items
    Spree::Backend::Config.configure do |config|
      config.menu_items << config.class::MenuItem.new(
        [:vendors],
        'users',
        label: 'marketplace.vendors.title',
        icon: 'store-alt',
        condition: -> { can?(:admin, Spree::Vendor) },
        partial: 'spree/admin/shared/marketplace_sub_menu'
      )
    end
    
    # API versioning support
    if Spree::Api::Engine.respond_to?(:version)
      initializer 'spree_marketplace.api' do
        Rails.application.routes.append do
          mount SpreeMarketplace::Engine => '/', :as => 'spree_marketplace'
        end
      end
    end
  end
end