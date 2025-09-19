# frozen_string_literal: true

require 'spree_core'
require 'spree_admin' 
require 'spree_api'

require 'state_machines-activerecord'
require 'friendly_id'
require 'acts-as-taggable-on'
require 'image_processing'

require 'spree_marketplace/version'
require 'spree_marketplace/configuration' 
require 'spree_marketplace/engine'

# Main module for SpreeMarketplace gem
# 
# This module provides multi-vendor marketplace functionality for Spree Commerce,
# including vendor onboarding, commission tracking, vendor dashboards, and
# comprehensive admin management tools.
module SpreeMarketplace
  # Singleton configuration instance
  mattr_accessor :configuration
  @@configuration = Configuration.new
  
  # Configure the gem
  #
  # @example Basic configuration
  #   SpreeMarketplace.configure do |config|
  #     config.default_commission_rate = 0.20
  #     config.auto_approve_vendors = false
  #     config.vendorized_models = %w[product variant stock_location]
  #   end
  #
  # @yield [Configuration] configuration object
  def self.configure
    yield(@@configuration) if block_given?
    @@configuration.validate_vendorized_models
  end
  
  # Access the current configuration
  #
  # @return [Configuration] the current configuration
  def self.configuration
    @@configuration
  end
  alias_method :config, :configuration
  
  # Reset configuration to defaults
  # Mainly used for testing
  #
  # @return [Configuration] new default configuration
  def self.reset_configuration!
    @@configuration = Configuration.new
  end
  
  # Check if gem is properly configured
  #
  # @return [Boolean] true if configuration is valid
  def self.configured?
    configuration.present? && configuration.vendorized_models.any?
  end
  
  # Get version information
  #
  # @return [Hash] version and compatibility information
  def self.version_info
    {
      gem_version: VERSION,
      spree_compatibility: '>= 4.6',
      ruby_compatibility: '>= 3.0',
      rails_compatibility: '>= 7.0'
    }
  end
  
  # Check if a model is vendorized
  #
  # @param model [String, Symbol, Class] model name or class
  # @return [Boolean] true if model is vendorized
  def self.vendorized?(model)
    model_name = case model
                 when String, Symbol
                   model.to_s
                 when Class
                   model.name.demodulize.underscore
                 else
                   return false
                 end
                 
    configuration.model_vendorized?(model_name)
  end
  
  # Calculate commission for given amount and rate
  #
  # @param amount [BigDecimal, Float] the base amount
  # @param vendor_rate [BigDecimal, Float, nil] vendor-specific commission rate
  # @return [Hash] commission breakdown
  def self.calculate_commission(amount, vendor_rate = nil)
    configuration.calculate_commission(amount, vendor_rate)
  end
  
  # Runtime information for debugging
  #
  # @return [Hash] runtime environment information
  def self.runtime_info
    {
      spree_version: Spree.version,
      rails_version: Rails.version,
      ruby_version: RUBY_VERSION,
      gem_version: VERSION,
      vendorized_models: configuration.vendorized_models,
      auto_approve_vendors: configuration.auto_approve_vendors,
      default_commission_rate: configuration.default_commission_rate
    }
  end
  
  # Exception classes for better error handling
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class VendorError < Error; end
  class CommissionError < Error; end
  class PayoutError < Error; end
end