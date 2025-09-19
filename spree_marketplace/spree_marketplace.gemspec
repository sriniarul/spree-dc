# encoding: UTF-8

require_relative 'lib/spree_marketplace/version'

Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = 'spree_marketplace'
  s.version     = SpreeMarketplace::VERSION
  s.authors     = ['Your Name']
  s.email       = ['your.email@example.com']
  s.summary     = 'Enterprise Multi-Vendor Marketplace for Spree Commerce'
  s.description = 'Complete multi-vendor marketplace solution with vendor onboarding, commission tracking, dashboard, and advanced management features for Spree Commerce'
  s.homepage    = 'https://github.com/yourusername/spree_marketplace'
  s.license     = 'MIT'
  s.required_ruby_version = '>= 3.0'
  s.required_rubygems_version = '>= 1.8.23'

  s.metadata = {
    'bug_tracker_uri'   => 'https://github.com/yourusername/spree_marketplace/issues',
    'changelog_uri'     => "https://github.com/yourusername/spree_marketplace/releases/tag/v#{s.version}",
    'documentation_uri' => 'https://github.com/yourusername/spree_marketplace/wiki',
    'source_code_uri'   => "https://github.com/yourusername/spree_marketplace/tree/v#{s.version}",
  }

  s.files = Dir['{app,config,db,lib,vendor}/**/*', 'LICENSE.md', 'Rakefile', 'README.md'].reject { |f| f.match(/^spec/) }
  s.require_path = 'lib'

  # Core Spree dependencies
  s.add_dependency 'spree_core', '>= 4.6'
  s.add_dependency 'spree_admin', '>= 4.6'
  s.add_dependency 'spree_api', '>= 4.6'
  
  # State machine and file processing
  s.add_dependency 'state_machines-activerecord', '~> 0.10'
  s.add_dependency 'image_processing', '~> 1.2'
  
  # Additional dependencies for enhanced functionality  
  s.add_dependency 'friendly_id', '~> 5.4'
  s.add_dependency 'acts-as-taggable-on', '~> 9.0'
  s.add_dependency 'chartkick', '~> 5.0'
  s.add_dependency 'groupdate', '~> 6.2'
  
  # Development dependencies
  s.add_development_dependency 'rspec-rails', '~> 6.0'
  s.add_development_dependency 'factory_bot_rails', '~> 6.2'
  s.add_development_dependency 'capybara', '~> 3.39'
  s.add_development_dependency 'selenium-webdriver', '~> 4.0'
  s.add_development_dependency 'database_cleaner', '~> 2.0'
  s.add_development_dependency 'simplecov', '~> 0.22'
  s.add_development_dependency 'rubocop', '~> 1.50'
  s.add_development_dependency 'rubocop-rails', '~> 2.19'
  s.add_development_dependency 'rubocop-rspec', '~> 2.20'
end