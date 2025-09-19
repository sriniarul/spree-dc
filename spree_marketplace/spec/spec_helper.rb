# frozen_string_literal: true

require 'spree/testing_support/preferences'
require 'spree/testing_support/authorization_helpers'
require 'spree/testing_support/capybara_ext'
require 'spree/testing_support/factories'
require 'spree/testing_support/caching'
require 'spree/testing_support/order_walkthrough'
require 'spree/testing_support/url_helpers'

# Load SpreeMarketplace test support
require 'spree_marketplace/testing_support/factories'

# Configure RSpec
RSpec.configure do |config|
  config.color = true
  config.infer_spec_type_from_file_location!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.mock_with :rspec
  
  # Use transactional fixtures for most tests
  config.use_transactional_fixtures = true
  
  # Include Spree test helpers
  config.include Spree::TestingSupport::Preferences
  config.include Spree::TestingSupport::UrlHelpers
  config.include Spree::TestingSupport::ControllerRequests, type: :controller
  
  # Clean up after tests
  config.before :suite do
    DatabaseCleaner.clean_with :truncation
  end
  
  config.before do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.start
    
    # Reset SpreeMarketplace configuration to defaults
    SpreeMarketplace.reset_configuration!
  end
  
  config.after do
    DatabaseCleaner.clean
  end
  
  # Shared examples
  config.shared_context_metadata_behavior = :apply_to_host_groups
  
  # Filter out slow tests by default
  config.filter_run_excluding slow: true unless ENV['RUN_SLOW_TESTS']
  
  # Profile slow examples
  config.profile_examples = 10 if ENV['PROFILE_TESTS']
  
  # Order specs randomly
  config.order = :random
  Kernel.srand config.seed
end

# SimpleCov configuration
if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.start 'rails' do
    add_filter '/spec/'
    add_filter '/lib/generators'
    add_group 'Models', 'app/models'
    add_group 'Controllers', 'app/controllers'
    add_group 'Serializers', 'app/serializers'
    add_group 'Views', 'app/views'
    add_group 'Helpers', 'app/helpers'
    add_group 'Jobs', 'app/jobs'
    add_group 'Mailers', 'app/mailers'
    
    minimum_coverage 90
  end
end