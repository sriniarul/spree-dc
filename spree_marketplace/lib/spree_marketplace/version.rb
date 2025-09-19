# frozen_string_literal: true

module SpreeMarketplace
  VERSION = '1.0.0'
  
  # Returns the current version of the SpreeMarketplace gem
  # This version follows semantic versioning (semver.org)
  #
  # @return [String] the current version
  def self.version
    VERSION
  end
  
  # Returns version information with additional metadata
  # Useful for debugging and support
  #
  # @return [Hash] version info with metadata  
  def self.version_info
    {
      version: VERSION,
      spree_version_requirement: '>= 4.6',
      ruby_version_requirement: '>= 3.0',
      rails_version_requirement: '>= 7.0'
    }
  end
end