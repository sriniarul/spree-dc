module SpreePushNotifications
  module Generators
    class InstallGenerator < Rails::Generators::Base
      class_option :auto_run_migrations, type: :boolean, default: false

      def add_javascripts
        append_to_file 'app/javascript/application.js', "import \"spree/push_notifications\"\n"
      end

      def add_stylesheets
        inject_into_file 'app/assets/stylesheets/application.css', before: " */" do
          " *= require spree/push_notifications\n"
        end
      end

      def install
        run 'bundle exec rails railties:install:migrations FROM=spree_push_notifications'
      end

      def run_migrations
        run_migrations = options[:auto_run_migrations] || ['', 'y', 'Y'].include?(ask('Would you like to run the migrations now? [Y/n]'))
        if run_migrations
          run 'bundle exec rails db:migrate'
        else
          puts 'Skipping rails db:migrate, don\'t forget to run it!'
        end
      end

      def copy_service_worker
        copy_file '../../../public/service-worker.js', 'public/service-worker.js'
      end

      def show_setup_instructions
        puts "\n" + "="*60
        puts "Spree Push Notifications Installation Complete!"
        puts "="*60

        puts "\nNext steps:"
        puts "1. Generate VAPID keys:"
        puts "   rails spree_push_notifications:generate_vapid_keys"

        puts "\n2. Add the environment variables to your app:"
        puts "   VAPID_PUBLIC_KEY=your_public_key"
        puts "   VAPID_PRIVATE_KEY=your_private_key"
        puts "   VAPID_SUBJECT=mailto:your_email@domain.com"

        puts "\n3. Add the notification banner to your layout:"
        puts "   <%= render 'spree/shared/push_notification_banner' %>"

        puts "\n4. Test the implementation:"
        puts "   rails spree_push_notifications:test"

        puts "\nFor more information, see the gem documentation."
        puts "="*60 + "\n"
      end
    end
  end
end