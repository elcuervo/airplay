require "airplay/errors"

module Airplay
  # Public: Process-scoped configuration.
  class Configuration
    LEVELS = %i[debug info warn error fatal].freeze
    DEFAULT_TIMEOUT = 5.0

    attr_accessor :autodiscover, :advertised_address, :output
    attr_reader :log_level, :timeout

    def initialize
      @log_level = :info
      @autodiscover = true
      @advertised_address = nil
      @timeout = DEFAULT_TIMEOUT
      @output = $stdout
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
  end
end
