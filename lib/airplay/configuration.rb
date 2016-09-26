require "logging"

# Public: Airplay core module
#
module Airplay
  # Public: Handles the Airplay configuration
  #
  class Configuration
    attr_accessor :log_level, :output, :autodiscover, :host, :port

    def initialize
      @log_level = :info
      @autodiscover = true
      @host = "0.0.0.0"
      @port = nil
      @output = Logging.appenders.stdout
    end

    # Public: Loads the configuration into the affected parts
    #
    # Returns nothing.
    #
    def load
      level = @log_level.is_a?(Symbol) ? @log_level : :info

      Logging.logger.root.appenders = @output
      Logging.logger.root.level = level
    end
  end
end
