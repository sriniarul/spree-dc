require_relative '../core/lib/spree/core/version'

Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = 'spree_multivendor'
  s.version     = Spree.version
  s.authors     = ['Spree Commerce']
  s.email       = 'hello@spreecommerce.org'
  s.summary     = 'Advanced Multi-Vendor Marketplace functionality for Spree'
  s.description = 'Provides advanced multi-vendor marketplace features including vendor registration, management, and storefront integration for Spree Commerce'
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

  s.files        = `git ls-files`.split("\n").select { |f| f.match(/^multivendor/) }
  s.require_path = 'lib'
  s.requirements << 'none'

  s.add_dependency 'spree', s.version
  s.add_dependency 'spree_core', s.version

  s.add_development_dependency 'spree_dev_tools'
end
