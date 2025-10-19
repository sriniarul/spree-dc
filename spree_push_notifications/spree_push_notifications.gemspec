lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'spree_push_notifications/version'

Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = 'spree_push_notifications'
  s.version     = SpreePushNotifications::VERSION
  s.summary     = 'Push notifications extension for Spree Commerce'
  s.description = 'Provides push notification functionality for Spree Commerce applications using Web Push API and service workers'
  s.required_ruby_version = '>= 3.0'

  s.author      = 'Spree Commerce'
  s.email       = 'spree@example.com'
  s.homepage    = 'https://github.com/spree/spree_push_notifications'
  s.license     = 'BSD-3-Clause'

  s.files       = `git ls-files`.split("\n")
  s.test_files  = `git ls-files -- spec/*`.split("\n")
  s.require_path = 'lib'
  s.requirements << 'none'

  s.add_dependency 'spree', '>= 4.2'
  s.add_dependency 'webpush', '~> 1.2'

  s.add_development_dependency 'rspec-rails'
end