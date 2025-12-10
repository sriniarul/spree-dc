module SpreeSocialMedia
  class Engine < Rails::Engine
    require 'spree/core'
    isolate_namespace Spree
    engine_name 'spree_social_media'

    config.autoload_paths += %W[#{config.root}/lib]

    # Load rake tasks
    rake_tasks do
      load File.join(root, 'lib', 'tasks', 'spree_social_media.rake') if File.exist?(File.join(root, 'lib', 'tasks', 'spree_social_media.rake'))
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

    initializer 'spree_social_media.environment', before: :load_config_initializers do |_app|
      SpreeSocialMedia::Config = SpreeSocialMedia::Configuration.new
    end

    # Add locale paths for internationalization
    initializer 'spree_social_media.locales' do |app|
      config.i18n.load_path += Dir[root.join('config', 'locales', '*.{rb,yml}')]
    end

    # Register migration paths
    initializer 'spree_social_media.migrations' do |app|
      unless app.root.to_s.match root.to_s
        config.paths['db/migrate'].expanded.each do |expanded_path|
          app.config.paths['db/migrate'] << expanded_path
        end
      end
    end

    # Configure omniauth for social media platforms
    initializer 'spree_social_media.omniauth', after: 'devise.omniauth' do |app|
      if SpreeSocialMedia::Config.facebook_configured?
        app.middleware.use OmniAuth::Builder do
          provider :facebook, SpreeSocialMedia::Config.facebook_app_id, SpreeSocialMedia::Config.facebook_app_secret,
                   scope: 'pages_manage_posts,pages_read_engagement,pages_manage_metadata,instagram_basic,instagram_content_publish'
        end
      end

      if SpreeSocialMedia::Config.youtube_configured?
        app.middleware.use OmniAuth::Builder do
          provider :google_oauth2, SpreeSocialMedia::Config.youtube_client_id, SpreeSocialMedia::Config.youtube_client_secret,
                   scope: 'https://www.googleapis.com/auth/youtube.upload,https://www.googleapis.com/auth/youtube.readonly'
        end
      end
    end

    # Add social media permissions to Spree abilities
    initializer 'spree_social_media.abilities', after: 'spree.environment' do |app|
      if defined?(Spree::Ability)
        Spree::Ability.register_ability(Spree::SocialMediaAbility)
      end
    end

    # Register social media navigation partial with admin navigation system
    initializer 'spree_social_media.admin_navigation', after: 'spree.environment' do |app|
      if defined?(Spree::Admin::Config)
        Spree::Admin::Config.store_nav_partials << 'spree/admin/shared/sidebar/marketing_nav'
      end
    end

    # Register product table partials for social media actions
    config.to_prepare do
      Rails.application.config.spree_admin.products_table_row_partials ||= []
      Rails.application.config.spree_admin.products_table_row_partials << 'spree/admin/products/social_media_actions' unless Rails.application.config.spree_admin.products_table_row_partials.include?('spree/admin/products/social_media_actions')

      Rails.application.config.spree_admin.products_table_header_partials ||= []
      Rails.application.config.spree_admin.products_table_header_partials << 'spree/admin/products/social_media_header' unless Rails.application.config.spree_admin.products_table_header_partials.include?('spree/admin/products/social_media_header')

      Rails.application.config.spree_admin.products_header_partials ||= []
      Rails.application.config.spree_admin.products_header_partials << 'spree/admin/products/image_gallery_modal' unless Rails.application.config.spree_admin.products_header_partials.include?('spree/admin/products/image_gallery_modal')
    end

    # Override vendor navigation to include social media
    config.after_initialize do
      if defined?(SpreeMultivendor) && Rails.env.development?
        # Only override navigation in development mode
        # In production, this should be handled by view precedence
      end
    end

    # Configure Sidekiq for background jobs
    initializer 'spree_social_media.sidekiq' do |app|
      if defined?(Sidekiq)
        Sidekiq.configure_server do |config|
          config.on(:startup) do
            # Load social media job schedules if using sidekiq-scheduler
            if defined?(Sidekiq::Scheduler)
              Sidekiq.schedule = YAML.load_file(Engine.root.join('config', 'schedule.yml')) if File.exist?(Engine.root.join('config', 'schedule.yml'))
              Sidekiq::Scheduler.reload_schedule!
            end
          end
        end
      end
    end
  end
end