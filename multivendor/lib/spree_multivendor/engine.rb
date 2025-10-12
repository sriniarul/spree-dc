module SpreeMultivendor
  class Engine < Rails::Engine
    require 'spree/core'
    isolate_namespace Spree
    engine_name 'spree_multivendor'

    config.autoload_paths += %W[#{config.root}/lib]

    # Load rake tasks
    rake_tasks do
      load File.join(root, 'lib', 'tasks', 'spree_multivendor.rake')
    end

    # Load generators
    config.generators do |g|
      g.test_framework :rspec
    end

    def self.activate
      Dir.glob(File.join(File.dirname(__FILE__), '../../app/**/*_decorator*.rb')) do |c|
        Rails.configuration.cache_classes ? require(c) : load(c)
      end
    end

    config.to_prepare(&method(:activate).to_proc)

    initializer 'spree_multivendor.environment', before: :load_config_initializers do |_app|
      SpreeMultivendor::Config = SpreeMultivendor::Configuration.new
    end

    # Add locale paths for internationalization
    initializer 'spree_multivendor.locales' do |app|
      config.i18n.load_path += Dir[root.join('config', 'locales', '*.{rb,yml}')]
    end



    # Register migration paths
    initializer 'spree_multivendor.migrations' do |app|
      unless app.root.to_s.match root.to_s
        config.paths['db/migrate'].expanded.each do |expanded_path|
          app.config.paths['db/migrate'] << expanded_path
        end
      end
    end
  end
end