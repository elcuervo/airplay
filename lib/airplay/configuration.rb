require "log4r/config"
require "airplay/logger"

# Public: Airplay core module
#
module Airplay
  # Public: Handles the Airplay configuration
  #
  class Configuration
    attr_accessor :log_level, :output, :autodiscover, :host, :port

    def initialize
      Log4r.define_levels(*Log4r::Log4rConfig::LogLevels)

      @log_level = Log4r::ERROR
      @autodiscover = true
      @host = "0.0.0.0"
      @port = nil
      @output = Log4r::Outputter.stdout
    end

    # Public: Loads the configuration into the affected parts
    #
    # Returns nothing.
    #
    def load
      level = if @log_level.is_a?(Fixnum)
                @log_level
              else
                Log4r.const_get(@log_level.upcase)
              end

      Log4r::Logger.root.add @output
      Log4r::Logger.root.level = level
      Celluloid.logger = Airplay::Logger.new("airplay::celluloid")
    end
  end
end
