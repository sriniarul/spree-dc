namespace :spree_multivendor do
  namespace :db do
    desc 'Load seed data for Spree Multivendor'
    task seed: :environment do
      puts 'Loading Spree Multivendor seed data...'

      # Create default vendor configurations
      puts '- Setting up default multivendor configurations'
      SpreeMultivendor::Config.vendor_approval_required = true
      SpreeMultivendor::Config.vendor_registration_enabled = true
      SpreeMultivendor::Config.admin_email_on_vendor_registration = true
      SpreeMultivendor::Config.vendor_can_edit_products = true
      SpreeMultivendor::Config.vendor_can_manage_orders = true
      SpreeMultivendor::Config.vendor_auto_approve_products = false

      puts 'Spree Multivendor seed data loaded successfully!'
    end

    desc 'Load sample vendor data for Spree Multivendor'
    task sample: :environment do
      puts 'Loading Spree Multivendor sample data...'

      # Only load if we're in development environment
      unless Rails.env.development?
        puts 'Sample data loading is only available in development environment'
        exit
      end

      # Create sample countries if they don't exist
      usa = Spree::Country.find_or_create_by(iso: 'US', name: 'United States')
      canada = Spree::Country.find_or_create_by(iso: 'CA', name: 'Canada')
      uk = Spree::Country.find_or_create_by(iso: 'GB', name: 'United Kingdom')

      # Create sample users for vendors
      sample_users = []

      3.times do |i|
        user = Spree.user_class.find_or_create_by(email: "vendor#{i + 1}@example.com") do |u|
          u.first_name = ['John', 'Jane', 'Mike'][i]
          u.last_name = ['Smith', 'Johnson', 'Davis'][i]
          u.password = u.password_confirmation = 'spree123'
        end
        sample_users << user
      end

      # Create sample vendors
      sample_vendors = [
        {
          name: 'TechNova Solutions',
          legal_name: 'TechNova Solutions LLC',
          business_type: 'Limited Liability Company (LLC)',
          trade_name: 'TechNova',
          registration_number: 'LLC-2023-001234',
          incorporation_date: 2.years.ago.to_date,
          country_code: 'US',
          state_province: 'California',
          city: 'San Francisco',
          postal_code: '94107',
          address_line1: '123 Market Street',
          address_line2: 'Suite 456',
          phone_number: '+1 (555) 123-4567',
          website_url: 'https://technova.example.com',
          state: 'approved',
          user: sample_users[0]
        },
        {
          name: 'Artisan Crafts Co.',
          legal_name: 'Artisan Crafts Corporation',
          business_type: 'Corporation',
          trade_name: 'Artisan Crafts',
          registration_number: 'CORP-2023-005678',
          incorporation_date: 3.years.ago.to_date,
          country_code: 'CA',
          state_province: 'Ontario',
          city: 'Toronto',
          postal_code: 'M5V 3M2',
          address_line1: '456 Queen Street West',
          phone_number: '+1 (416) 555-7890',
          website_url: 'https://artisancrafts.example.com',
          state: 'approved',
          user: sample_users[1]
        },
        {
          name: 'Fresh Foods Market',
          legal_name: 'Fresh Foods Market Limited',
          business_type: 'Private Limited Company',
          registration_number: 'LTD-2024-009876',
          incorporation_date: 1.year.ago.to_date,
          country_code: 'GB',
          state_province: 'England',
          city: 'London',
          postal_code: 'SW1A 1AA',
          address_line1: '789 High Street',
          phone_number: '+44 20 7946 0958',
          state: 'pending',
          user: sample_users[2]
        }
      ]

      sample_vendors.each do |vendor_attrs|
        vendor = Spree::Vendor.find_or_create_by(registration_number: vendor_attrs[:registration_number]) do |v|
          vendor_attrs.each { |key, value| v.send("#{key}=", value) }
        end
        puts "- Created sample vendor: #{vendor.display_name} (#{vendor.state})"
      end

      puts "Spree Multivendor sample data loaded successfully!"
      puts "Sample vendors created:"
      Spree::Vendor.all.each do |vendor|
        puts "  - #{vendor.display_name} (#{vendor.state.capitalize})"
      end
    end
  end

  desc 'Install all migrations (Spree Core, API, and Multivendor)'
  task 'install:migrations': :environment do
    puts 'Installing all Spree migrations...'

    # Install all necessary migrations
    puts '- Installing Active Storage migrations...'
    Rake::Task['active_storage:install:migrations'].invoke

    puts '- Installing Action Text migrations...'
    Rake::Task['action_text:install:migrations'].invoke

    puts '- Installing Spree Core migrations...'
    Rake::Task['spree:install:migrations'].invoke

    puts '- Installing Spree API migrations...'
    Rake::Task['spree_api:install:migrations'].invoke

    puts '- Installing Spree Multivendor migrations...'
    Rake::Task['railties:install:migrations'].invoke('FROM=spree_multivendor')

    puts 'All migrations installed successfully!'
    puts 'Run "rake db:migrate" to apply the migrations.'
  end

  desc 'Install Spree Multivendor'
  task install: :environment do
    puts 'Installing Spree Multivendor...'

    # Install all migrations
    Rake::Task['spree_multivendor:install:migrations'].invoke

    # Run migrations
    Rake::Task['db:migrate'].invoke

    # Load seed data
    Rake::Task['spree_multivendor:db:seed'].invoke

    puts 'Spree Multivendor installed successfully!'
    puts 'Visit /vendors/register to access vendor registration'
    puts 'Visit /admin/vendors to manage vendors'
  end
end