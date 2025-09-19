# frozen_string_literal: true

require 'rails/generators'

module SpreeMarketplace
  module Generators
    class InstallGenerator < Rails::Generators::Base
      class_option :migrate, type: :boolean, default: true, 
                   banner: 'Run spree_marketplace migrations'
      class_option :seed, type: :boolean, default: true,
                   banner: 'Load spree_marketplace seed data'
      class_option :sample, type: :boolean, default: false,
                   banner: 'Create sample vendor data'
      class_option :auto_accept, type: :boolean, default: false,
                   banner: 'Accept all prompts automatically'

      source_root File.expand_path('templates', __dir__)

      def self.source_paths
        paths = superclass.source_paths
        paths << File.expand_path('templates', __dir__)
        paths.flatten
      end

      def add_files
        template 'config/initializers/spree_marketplace.rb', 'config/initializers/spree_marketplace.rb'
      end

      def add_migrations
        run 'bundle exec rake railties:install:migrations FROM=spree_marketplace'
      end

      def run_migrations
        return unless options[:migrate]

        res = ask 'Would you like to run the migrations now? [Y/n]'
        if options[:auto_accept] || res.blank? || res.casecmp('y').zero?
          run 'bundle exec rake db:migrate'
        else
          puts 'Skipping rake db:migrate, don\'t forget to run it!'
        end
      end

      def load_seed_data
        return unless options[:seed]

        res = ask 'Would you like to load the seed data? [Y/n]'
        if options[:auto_accept] || res.blank? || res.casecmp('y').zero?
          run 'bundle exec rake spree_marketplace:seed'
        else
          puts 'Skipping spree_marketplace:seed, don\'t forget to run it!'
        end
      end

      def create_sample_data
        return unless options[:sample]

        res = ask 'Would you like to create sample vendor data? [y/N]'
        if res.casecmp('y').zero?
          run 'bundle exec rake spree_marketplace:sample'
        end
      end

      def show_readme
        readme 'README' if behavior == :invoke
      end

      private

      def readme(path)
        say_status 'readme', path, :cyan
        say IO.read(find_in_source_paths(path)), :green
      end
    end
  end
end