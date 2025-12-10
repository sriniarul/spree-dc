require_relative '../core/lib/spree/core/version'

Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = 'spree_social_media'
  s.version     = Spree.version
  s.authors     = ['Spree Commerce']
  s.email       = 'hello@spreecommerce.org'
  s.summary     = 'Social Media Integration for Spree Commerce'
  s.description = 'Provides comprehensive social media integration features including vendor social media account management, automated product posting, analytics tracking, and campaign management for Facebook, Instagram, WhatsApp, YouTube, and TikTok platforms'
  s.homepage    = 'https://spreecommerce.org'
  s.license     = 'AGPL-3.0-or-later'

  s.metadata = {
    "bug_tracker_uri"   => "https://github.com/spree/spree/issues",
    "changelog_uri"     => "https://github.com/spree/spree/releases/tag/v#{s.version}",
    "documentation_uri" => "https://docs.spreecommerce.org/",
    "source_code_uri"   => "https://github.com/spree/spree/tree/v#{s.version}",
  }

  s.required_ruby_version = '>= 3.0'
  s.required_rubygems_version = '>= 1.8.23'

  s.files        = `git ls-files`.split("\n").select { |f| f.match(/^social_media/) }
  s.require_path = 'lib'
  s.requirements << 'none'

  s.add_dependency 'spree', s.version
  s.add_dependency 'spree_core', s.version

  # OAuth dependencies for social media platforms
  s.add_dependency 'omniauth', '~> 2.0'
  s.add_dependency 'omniauth-facebook', '~> 9.0'
  s.add_dependency 'omniauth-google-oauth2', '~> 1.0'
  s.add_dependency 'omniauth-rails_csrf_protection', '~> 1.0'

  # HTTP client for API requests
  s.add_dependency 'httparty', '~> 0.21'
  s.add_dependency 'faraday', '~> 2.0'
  s.add_dependency 'faraday-retry', '~> 2.0'

  # Background job processing
  s.add_dependency 'sidekiq', '~> 7.0'
  s.add_dependency 'sidekiq-scheduler', '~> 5.0'

  # Image processing for social media posts
  s.add_dependency 'mini_magick', '~> 4.11'

  # JSON handling
  s.add_dependency 'multi_json', '~> 1.15'

  s.add_development_dependency 'spree_dev_tools'
end