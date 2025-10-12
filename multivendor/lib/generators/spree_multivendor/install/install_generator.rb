module SpreeMultivendor
  module Generators
    class InstallGenerator < Rails::Generators::Base
      class_option :migrate, type: :boolean, default: true, banner: 'Run Spree Multivendor migrations'
      class_option :seed, type: :boolean, default: true, banner: 'Load seed data'
      class_option :sample, type: :boolean, default: false, banner: 'Load sample vendor data'

      def self.source_paths
        paths = []
        paths << File.expand_path('templates', __dir__)
        paths << File.expand_path('../templates', __FILE__)
        paths.flatten
      end

      def add_javascripts
        append_file 'vendor/assets/javascripts/spree/frontend/all.js', "//= require spree/frontend/spree_multivendor\n"
        append_file 'vendor/assets/javascripts/spree/backend/all.js', "//= require spree/backend/spree_multivendor\n"
      end

      def add_stylesheets
        inject_into_file 'vendor/assets/stylesheets/spree/frontend/all.css', " *= require spree/frontend/spree_multivendor\n", before: /\*\//, verbose: true
        inject_into_file 'vendor/assets/stylesheets/spree/backend/all.css', " *= require spree/backend/spree_multivendor\n", before: /\*\//, verbose: true
      end

      def add_migrations
        say_status :copying, 'migrations from all sources'
        # Copy migrations from all Spree engines and multivendor
        run 'bundle exec rake active_storage:install:migrations'
        run 'bundle exec rake action_text:install:migrations'
        run 'bundle exec rake spree:install:migrations'
        run 'bundle exec rake spree_api:install:migrations'
        run 'bundle exec rake railties:install:migrations FROM=spree_multivendor'
      end

      def run_migrations
        run_migrations = options[:migrate] || ['', 'y', 'Y'].include?(ask('Would you like to run the migrations now? [Y/n]'))
        if run_migrations
          run 'bundle exec rake db:migrate'
        else
          puts 'Skipping rake db:migrate, don\'t forget to run it!'
        end
      end

      def load_seed_data
        if options[:seed] || ['', 'y', 'Y'].include?(ask('Would you like to load the seed data? [Y/n]'))
          run 'bundle exec rake spree_multivendor:db:seed'
        else
          puts 'Skipping spree_multivendor:db:seed, don\'t forget to run it!'
        end
      end

      def load_sample_data
        if options[:sample] || ['', 'n', 'N', 'no'].include?(ask('Would you like to load sample vendor data? [y/N]'))
          run 'bundle exec rake spree_multivendor:db:sample'
        else
          puts 'Skipping spree_multivendor:db:sample'
        end
      end

      def notify_about_configuration
        puts '*' * 50
        puts 'Spree Multivendor has been installed successfully!'
        puts '*' * 50
        puts ''
        puts 'Next steps:'
        puts '1. Configure vendor settings in config/initializers/spree.rb:'
        puts '   SpreeMultivendor::Config.vendor_approval_required = true'
        puts '   SpreeMultivendor::Config.vendor_registration_enabled = true'
        puts ''
        puts '2. Vendor registration is now available at: /vendors/register'
        puts '3. Admin vendor management is available at: /admin/vendors'
        puts ''
        puts 'For more information, visit: https://github.com/spree/spree-multivendor'
        puts '*' * 50
      end
    end
  end
end