require "airplay/errors"

module Airplay
  # Public: Process-scoped configuration.
  class Configuration
    LEVELS = %i[debug info warn error fatal].freeze
    DEFAULT_TIMEOUT = 5.0

    attr_accessor :autodiscover, :advertised_address, :output,
                  :discovery_port, :discovery_interfaces, :media_port, :digest_username
    attr_reader :log_level, :timeout, :discovery_window

    def initialize
      @log_level = :info
      @autodiscover = true
      @advertised_address = nil
      @timeout = DEFAULT_TIMEOUT
      @output = $stdout
      @discovery_port = 5353
      @discovery_interfaces = nil
      @discovery_window = 2.0
      @media_port = 0
      @digest_username = nil
    end

    def log_level=(value)
      value = value.to_sym
      unless LEVELS.include?(value)
        raise ConfigurationError, "unknown log level #{value.inspect}"
      end
      @log_level = value
    end

    def timeout=(value)
      value = Float(value)
      raise ConfigurationError, "timeout must be positive" unless value.positive?
      @timeout = value
    end

    def discovery_window=(value)
      value = Float(value)
      raise ConfigurationError, "discovery window must be positive" unless value.positive?
      @discovery_window = value
    end
  end
end
