require 'log4r/config'

module Airplay
  # Public: Handles the Airplay configuration
  #
  class Configuration
    attr_accessor :log_level, :output

    def initialize
      Log4r.define_levels(*Log4r::Log4rConfig::LogLevels)

      @log_level = Log4r::WARN
      @output = Log4r::Outputter.stdout
    end

    # Public: Loads the configuration into the affected parts
    #
    def load
      level = if @log_level.is_a?(Fixnum)
                @log_level
              else
                Log4r.const_get(@log_level.upcase)
              end

      Log4r::Logger.root.add @output
      Log4r::Logger.root.level = level
    end
  end
end
