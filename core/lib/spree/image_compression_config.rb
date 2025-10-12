module Spree
  class ImageCompressionConfig
    include ActiveSupport::Configurable

    config_accessor :max_file_size, default: 5.megabytes
    config_accessor :compression_quality, default: 0.8
    config_accessor :max_width, default: 2048
    config_accessor :max_height, default: 2048
    config_accessor :enabled, default: true
    config_accessor :compress_on_client, default: true
    config_accessor :compress_on_server, default: true
  end
end