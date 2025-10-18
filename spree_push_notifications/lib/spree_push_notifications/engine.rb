module SpreePushNotifications
  class Engine < Rails::Engine
    require 'spree/core'
    isolate_namespace Spree
    engine_name 'spree_push_notifications'

    config.autoload_paths += %W(#{config.root}/lib)

    # use rspec for tests
    config.generators do |g|
      g.test_framework :rspec
    end

    def self.activate
      Dir.glob(File.join(File.dirname(__FILE__), '../../app/**/*_decorator*.rb')) do |c|
        Rails.configuration.cache_classes ? require(c) : load(c)
      end
    end

    # Admin navigation will be handled via view override

    config.to_prepare(&method(:activate).to_proc)

    initializer 'spree_push_notifications.assets' do |app|
      app.config.assets.paths << root.join('app', 'assets', 'javascripts')
      app.config.assets.paths << root.join('app', 'assets', 'stylesheets')
      app.config.assets.precompile += %w[
        spree/push_notifications.js
        spree/push_notifications.css
      ]
    end

    initializer 'spree_push_notifications.importmap', before: 'importmap' do |app|
      app.config.importmap.paths << root.join('config/importmap.rb') if app.config.respond_to?(:importmap)
    end
  end
end